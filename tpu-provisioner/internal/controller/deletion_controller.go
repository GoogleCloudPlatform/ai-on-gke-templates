package controller

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/GoogleCloudPlatform/ai-on-gke/tpu-provisioner/internal/cloud"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	ctrllog "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
	"sigs.k8s.io/controller-runtime/pkg/source"
)

// DeletionReconciler watches Pods and Nodes and deletes Node Pools.
type DeletionReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder
	Provider cloud.Provider

	NodeCriteria               NodeCriteria
	NodePoolsMarkedForDeletion sync.Map
}

type NodeCriteria struct {
	MinLifetime time.Duration

	// PoolDeletionDelay is the interval between the first and
	// second node pool deletion checks. Once the node pool deletion check
	// has passed twice, the node pool can be safely deleted. This second
	// check is ensure the node pool is not prematurely deleted, in the case
	// where a JobSet is restarted, but no pods have been created yet.
	PoolDeletionDelay time.Duration
}

//+kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="",resources=nodes/status,verbs=get;update;patch
//+kubebuilder:rbac:groups="",resources=nodes/finalizers,verbs=update

func (r *DeletionReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	lg := ctrllog.FromContext(ctx)

	lg.V(3).Info("Reconciling Node")

	var node corev1.Node
	if err := r.Get(ctx, req.NamespacedName, &node); err != nil {
		if apierrors.IsNotFound(err) {
			// Don't requeue, Node no longer exists (or does not exist in the cache).
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, fmt.Errorf("getting node: %w", err)
	}

	// NOTE: Because of the cache filter in main.go, this check should always evaluate to false.
	if node.GetLabels()[cloud.LabelNodepoolManager] != cloud.LabelNodepoolManagerTPUPodinator {
		lg.V(3).Info("Node was not provisioned by this controller, ignoring")
		return ctrl.Result{}, nil
	}

	nodePoolLabelKey := r.Provider.NodePoolLabelKey()
	nodePoolName, ok := node.GetLabels()[nodePoolLabelKey]
	if !ok {
		lg.V(3).Info("No node pool label found on node, ignoring", "labelKey", nodePoolLabelKey)
		return ctrl.Result{}, nil
	}

	lg = lg.WithValues("nodePoolName", nodePoolName)

	// Avoid noisy reconciliation when nodes are shutting down.
	for _, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady &&
			c.Status == corev1.ConditionUnknown {
			const unknownThreshold = 10 * time.Minute
			if unknownDuration := time.Since(c.LastTransitionTime.Time); unknownDuration >= unknownThreshold {
				lg.Info("Node has been in an Unknown state for too long, deleting Node Pool", "timeSinceLastTransition", time.Since(c.LastTransitionTime.Time))
				return r.deleteNodePool(&node, nodePoolName)
			} else {
				waitTime := unknownThreshold - unknownDuration + time.Minute
				lg.Info("Node is in an Unknown state, waiting",
					"timeSinceLastTransition", time.Since(c.LastTransitionTime.Time),
					"waiting", waitTime,
				)
				return ctrl.Result{RequeueAfter: waitTime}, nil
			}
		}
		if c.Type == corev1.NodeReady &&
			c.Status == corev1.ConditionFalse &&
			c.Reason == "KubeletNotReady" &&
			c.Message == "node is shutting down" {
			lg.V(3).Info("Node is shutting down, ignoring")
			return ctrl.Result{}, nil
		}
	}

	// Ensure node was not just created to make sure Pods have had time to schedule.
	if since := time.Since(node.GetCreationTimestamp().Time); since < r.NodeCriteria.MinLifetime {
		wait := r.NodeCriteria.MinLifetime - since + time.Second
		lg.V(3).Info("Node was just created, ignoring", "waiting", wait)
		return ctrl.Result{RequeueAfter: wait}, nil
	}

	// Get all node in the same node pool.
	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels{nodePoolLabelKey: nodePoolName}); err != nil {
		return ctrl.Result{}, fmt.Errorf("listing nodes in node pool: %w", err)
	}

	// Ensure no user-Pods are running or pending on the node pool.
	for _, n := range nodes.Items {
		var pods corev1.PodList
		// TODO: Can this be done with a "contains" field match to avoid the outer node loop?
		if err := r.List(ctx, &pods, client.MatchingFields{".spec.nodeName": n.GetName()}); err != nil {
			return ctrl.Result{}, fmt.Errorf("listing pods for node: %w", err)
		}

		for _, p := range pods.Items {
			// Ignore Pods that have finished.
			if isDone(&p) {
				continue
			}

			// Don't let system Pods prevent downsizing.
			if p.GetNamespace() == "kube-system" {
				continue
			}

			if owner := metav1.GetControllerOf(&p); owner != nil {
				if owner.Kind == "DaemonSet" || owner.Kind == "Node" {
					continue
				}
			}

			// Must be a user-Pod.
			lg.V(3).Info("Node in node pool has user pod running, ignoring",
				"podNode", n.GetName(), "podName", p.GetName(), "podNamespace", p.GetNamespace())
			return ctrl.Result{}, nil
		}
	}

	// If node pool passes deletion check once, reconcile again in a few seconds to give
	// time for a restarting JobSet to recreate the Jobs and pods that may be assigned to
	// this node pool.
	value, exists := r.NodePoolsMarkedForDeletion.Load(nodePoolName)
	if !exists {
		lg.Info(fmt.Sprintf("Node pool %q passed deletion check once", nodePoolName))
		r.NodePoolsMarkedForDeletion.Store(nodePoolName, time.Now())
		return ctrl.Result{RequeueAfter: r.NodeCriteria.PoolDeletionDelay}, nil
	}

	// If we haven't reached the node pool deletion check interval, this reconcile was
	// caused by something else, we can return early, and wait for the manually requeued
	// reconcile we did after the first deletion check passed.
	firstDeletionCheckTime := value.(time.Time)
	if time.Now().Sub(firstDeletionCheckTime) < r.NodeCriteria.PoolDeletionDelay {
		return ctrl.Result{}, nil
	}

	lg.Info("Node pool passed deletion check twice. Ensuring Node Pool is deleted")
	return r.deleteNodePool(&node, nodePoolName)
}

func (r *DeletionReconciler) deleteNodePool(node *corev1.Node, nodePoolName string) (ctrl.Result, error) {
	// If this point is reached, the node pool has passed the deletion check twice
	// and can be deleted.
	if err := r.Provider.DeleteNodePoolForNode(node, "no user Pods are running on any of the Nodes in this node pool"); err != nil {
		if errors.Is(err, cloud.ErrDuplicateRequest) {
			return ctrl.Result{}, nil
		} else {
			return ctrl.Result{}, err
		}
	}

	// Remove node pool from the map tracking node pools marked for deletion, in case the JobSet
	// is reran in the future, as this will result in node pools with the same name being recreated,
	// and we want those to start with 0 deletion checks.
	r.NodePoolsMarkedForDeletion.Delete(nodePoolName)

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *DeletionReconciler) SetupWithManager(mgr ctrl.Manager) error {
	if err := mgr.GetFieldIndexer().IndexField(context.Background(), &corev1.Pod{}, ".spec.nodeName", func(rawObj client.Object) []string {
		pod := rawObj.(*corev1.Pod)
		return []string{pod.Spec.NodeName}
	}); err != nil {
		return err
	}

	if r.NodeCriteria.MinLifetime == 0 {
		return fmt.Errorf("NodeCriteria.MinLifetime must be set")
	}

	// NOTE: Direct Node watches are filtered based on labels in main.go.
	//       However, Reconcile() can still be called for non-filtered Nodes
	//       Because the of Watch on Pods below.
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Node{}).
		Watches(&source.Kind{Type: &corev1.Pod{}}, handler.EnqueueRequestsFromMapFunc(handler.MapFunc(nodeForPod))).
		Complete(r)
}

func nodeForPod(obj client.Object) []reconcile.Request {
	pod := obj.(*corev1.Pod)
	if nodeName := pod.Spec.NodeName; nodeName != "" {
		return []reconcile.Request{
			{NamespacedName: types.NamespacedName{Name: nodeName}},
		}
	}
	return []reconcile.Request{}
}
