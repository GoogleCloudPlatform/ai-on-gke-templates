package cloud

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	containerv1beta1 "google.golang.org/api/container/v1beta1"
	"google.golang.org/api/googleapi"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	jobset "sigs.k8s.io/jobset/api/jobset/v1alpha2"
)

var log = logf.Log.WithName("provider")

const (
	// GKE labels
	GKETPUNodeSelector         = "cloud.google.com/gke-tpu-topology"
	GKEAcceleratorNodeSelector = "cloud.google.com/gke-tpu-accelerator"
	GKENodePoolNameLabel       = "cloud.google.com/gke-nodepool"

	// ICIResiliencyLabel is used for disabling ICI resiliency, by default if not specified TPU slice
	// is created in the ICI resilient mode. To disable the ICI resilient, workload needs
	// to use node selector or affinity cloud.google.com/gke-tpu-ici-resiliency=false.
	ICIResiliencyLabel = "cloud.google.com/gke-tpu-ici-resiliency"

	// LocationHintLabel is used for passing in a desired borg cell the node pool MIG should be
	// provisioned in.
	LocationHintLabel = "cloud.google.com/gke-location-hint"

	// Supported accelerator types
	V4PodSliceAccelerator  = "tpu-v4-podslice"
	V5ePodSliceAccelerator = "tpu-v5-lite-podslice"
	V5pPodSliceAccelerator = "tpu-v5p-slice"
	V6eSliceAccelerator    = "tpu-v6e-slice"

	// Resource type labels
	GoogleTPUResource = "google.com/tpu"
	gcpLabelPrefix    = "cloud.google.com/"
	googleLabelPrefix = "google.com/"

	// Default max pods per node is 110, but a lower value is necessary for large scale clusters,
	// otherwise we'll run out of IP Space and provisioning will fail.
	// 15 pods per node will work for small and large cluster sizes, given the TPU constraint of
	// 1 pod per TPU node + kube-system pods
	// TODO: move this to a environment variable
	maxPodsPerNode = 15

	// Constants for node pool naming conventions.
	maxJobSetPrefixLength = 34
	jobKeySuffixLength    = 5
)

var _ Provider = &GKE{}

type GKE struct {
	Service        *containerv1beta1.Service
	ClusterContext GKEContext

	Recorder record.EventRecorder

	inProgressDeletesNPName sync.Map
	inProgressCreatesNPName sync.Map
	inProgressCreatesJobKey sync.Map
}

func (g *GKE) NodePoolLabelKey() string { return GKENodePoolNameLabel }

func (g *GKE) EnsureNodePoolForPod(p *corev1.Pod, why string) error {
	name, err := podToNodePoolName(p)
	if err != nil {
		return err
	}

	exists, err := g.nodePoolExists(name)
	if err != nil {
		return fmt.Errorf("checking if node pool exists: %w", err)
	}
	if exists {
		return nil
	}

	np, err := g.nodePoolForPod(name, p)
	if err != nil {
		return fmt.Errorf("determining node pool for pod: %w", err)
	}

	req := &containerv1beta1.CreateNodePoolRequest{
		NodePool: np,
		Parent:   g.ClusterContext.ClusterName(),
	}

	// Due to concurrent reconciles, multiple creates for the same
	// Node Pool will occur at the same time. The result is an error:
	// "do: googleapi: Error 400: Cluster is running incompatible operation ..."
	// To avoid a bunch of failed requests, we dedeuplicate here.
	if _, inProgress := g.inProgressCreatesNPName.Load(name); inProgress {
		return fmt.Errorf("creation ongoing for node pool name: %v: %w", name, ErrDuplicateRequest)
	}
	g.inProgressCreatesNPName.Store(name, struct{}{})
	defer g.inProgressCreatesNPName.Delete(name)

	// A restarting JobSet will trigger a new Node Pool creation.
	// The current creation attempt might overlap with the previous one,
	// which could still be ongoing, so we need to deduplicate.
	// This works because job-key remains constant across restarts.
	// NOTE: These checks dont work across controller restarts.
	if jobKey := p.Labels[jobset.JobKey]; jobKey != "" {
		if _, inProgress := g.inProgressCreatesJobKey.Load(jobKey); inProgress {
			return fmt.Errorf("creation ongoing for job-key: %v: %w", jobKey, ErrDuplicateRequest)
		}
		g.inProgressCreatesJobKey.Store(jobKey, struct{}{})
		defer g.inProgressCreatesJobKey.Delete(jobKey)
	}

	// Get JobSet this pod is part of from the pod labels and log it.
	jobSetName := p.Labels[jobset.JobSetNameKey]
	g.Recorder.Eventf(p, corev1.EventTypeNormal, EventNodePoolCreationStarted, "Starting creation of Node Pool %s (size = %v) for JobSet %s because %s", name, np.InitialNodeCount, jobSetName, why)
	log.Info(fmt.Sprintf("creating node pool %s for jobset %s", np.Name, jobSetName))

	call := g.Service.Projects.Locations.Clusters.NodePools.Create(g.ClusterContext.ClusterName(), req)
	op, err := call.Do()
	if err != nil {
		g.Recorder.Eventf(p, corev1.EventTypeWarning, EventNodePoolCreationFailed, "Request to create Node Pool %s failed: %v.", name, err)
		return fmt.Errorf("do: %w", err)
	}

	if err := waitForGkeOp(g.Service, g.ClusterContext, op); err != nil {
		g.Recorder.Eventf(p, corev1.EventTypeWarning, EventNodePoolCreationFailed, "Operation to create Node Pool %s failed: %v.", name, err)
		return fmt.Errorf("waiting for operation: %w", err)
	}

	g.Recorder.Eventf(p, corev1.EventTypeNormal, EventNodePoolCreationSucceeded, "Successfully created Node Pool %s.", name)

	return nil
}

func (g *GKE) ListNodePools() ([]NodePoolRef, error) {
	var refs []NodePoolRef

	resp, err := g.Service.Projects.Locations.Clusters.NodePools.List(g.ClusterContext.ClusterName()).Do()
	if err != nil {
		return nil, fmt.Errorf("listing node pools: %w", err)

	}

	for _, np := range resp.NodePools {
		jsName, exists := np.Config.Labels[LabelJobSetName]
		if !exists {
			jsName = np.Config.Labels[LabelProvisionerNodepoolID]
		}
		jsNamespace, exists := np.Config.Labels[LabelJobSetNamespace]
		if !exists {
			jsNamespace = "default"
		}

		refs = append(refs, NodePoolRef{
			Name:    np.Name,
			Error:   np.Status == "ERROR",
			Message: np.StatusMessage,
			CreatedForJobSet: types.NamespacedName{
				Name:      jsName,
				Namespace: jsNamespace,
			},
		})
	}

	return refs, nil
}

func (g *GKE) DeleteNodePoolForNode(node *corev1.Node, why string) error {
	name, ok := node.GetLabels()[g.NodePoolLabelKey()]
	if !ok {
		return fmt.Errorf("node %q does not have node pool label", node.Name)
	}

	return g.DeleteNodePool(name, node, why)
}

func (g *GKE) DeleteNodePool(name string, eventObj client.Object, why string) error {
	// Due to concurrent reconciles, multiple deletes for the same
	// Node Pool will occur at the same time. The result is an error:
	// To avoid a bunch of failed requests, we dedeuplicate here.
	if _, inProgress := g.inProgressDeletesNPName.Load(name); inProgress {
		return ErrDuplicateRequest
	}
	g.inProgressDeletesNPName.Store(name, struct{}{})
	defer g.inProgressDeletesNPName.Delete(name)

	g.Recorder.Eventf(eventObj, corev1.EventTypeNormal, EventNodePoolDeletionStarted, "Starting deletion of Node Pool %s because %s", name, why)
	op, err := g.Service.Projects.Locations.Clusters.Delete(g.ClusterContext.NodePoolName(name)).Do()
	if err != nil {
		if gerr, ok := err.(*googleapi.Error); ok && gerr.Code == http.StatusNotFound {
			g.Recorder.Eventf(eventObj, corev1.EventTypeNormal, EventNodePoolNotFound, "Node pool not found - ignoring deletion attempt.", name)
			return nil
		}
		g.Recorder.Eventf(eventObj, corev1.EventTypeWarning, EventNodePoolDeletionFailed, "Request to delete Node Pool %s failed: %v.", name, err)
		return fmt.Errorf("deleting node pool %q: %w", name, err)
	}

	if err := waitForGkeOp(g.Service, g.ClusterContext, op); err != nil {
		g.Recorder.Eventf(eventObj, corev1.EventTypeWarning, EventNodePoolDeletionFailed, "Operation to delete Node Pool %s failed: %v.", name, err)
		return err
	}

	g.Recorder.Eventf(eventObj, corev1.EventTypeNormal, EventNodePoolDeletionSucceeded, "Successfully deleted Node Pool %s.", name)

	return nil
}

var ErrNodePoolStopping = errors.New("node pool stopping")

func (g *GKE) nodePoolExists(name string) (bool, error) {
	call := g.Service.Projects.Locations.Clusters.NodePools.Get(g.ClusterContext.NodePoolName(name))
	np, err := call.Do()
	if err == nil {
		return true, nil
	}
	if gerr, ok := err.(*googleapi.Error); ok && gerr.Code == http.StatusNotFound {
		return false, nil
	}
	if np.Status == "STOPPING" {
		return false, ErrNodePoolStopping
	}

	return false, err
}

func (g *GKE) nodePoolForPod(name string, p *corev1.Pod) (*containerv1beta1.NodePool, error) {
	ref := metav1.GetControllerOf(p)
	if ref == nil {
		// TODO: Allow for standalone Pods?
		return nil, errors.New("no owner reference")
	}

	jobSetName := p.Labels[jobset.JobSetNameKey]
	if jobSetName == "" {
		// This should never be reached due to the event filters in reconciler, but added just in case.
		return nil, fmt.Errorf("pod %s is not part of a jobset, not constructing node pool config for it", p.Name)
	}

	labels := map[string]string{
		// Used to keep track of what Node Pools this provisioner is responsible for.
		LabelNodepoolManager: LabelNodepoolManagerTPUPodinator,

		// Leave some bread crumbs:
		LabelParentKind: strings.ToLower(ref.Kind),
		LabelParentName: strings.ToLower(ref.Name),
		// Assuming a Namespaced parent here...
		LabelParentNamespace: strings.ToLower(p.Namespace),

		LabelJobSetName:      jobSetName,
		LabelJobSetNamespace: p.Namespace,
	}

	// Copy configured labels from the Pod to the Node.
	for _, key := range g.ClusterContext.PodToNodeLabels {
		if val, ok := p.Labels[key]; ok {
			labels[key] = val
		}
	}

	// Copy labels specified by annotation to the Node.
	for _, key := range strings.Split(getAnnotation(p, AnnotationCopyLabels), ",") {
		key = strings.TrimSpace(key)
		if key == "" {
			continue
		}
		if val, ok := p.Labels[key]; ok {
			labels[key] = val
		}
	}

	for labelKey, labelValue := range p.Spec.NodeSelector {
		switch labelKey {
		case ICIResiliencyLabel:
			labels[labelKey] = labelValue
		case LocationHintLabel:
			labels[labelKey] = labelValue
		default:
			// Don't copy GCP/Google labels onto the node.
			if !strings.HasPrefix(labelKey, gcpLabelPrefix) && !strings.HasPrefix(labelKey, googleLabelPrefix) {
				labels[labelKey] = labelValue
			}
		}
	}

	// Pod should already be filtered for this Node Selector at this point.
	tpuTopo, ok := p.Spec.NodeSelector[GKETPUNodeSelector]
	if !ok {
		return nil, fmt.Errorf("missing node selector key: %v", GKETPUNodeSelector)
	}
	accel, ok := p.Spec.NodeSelector[GKEAcceleratorNodeSelector]
	if !ok {
		return nil, fmt.Errorf("missing node selector key: %v", GKEAcceleratorNodeSelector)
	}
	tpuRequest, err := sumTPURequests(p)
	if err != nil {
		return nil, fmt.Errorf("summing TPU requests: %w", err)
	}

	nodeCount, err := tpuTopologyToNodeCount(accel, tpuTopo)
	if err != nil {
		return nil, fmt.Errorf("determining node count: %w", err)
	}
	machineType, err := tpuMachineType(accel, tpuRequest)
	if err != nil {
		return nil, fmt.Errorf("determining node count: %w", err)
	}

	var reservation *containerv1beta1.ReservationAffinity
	var taints []*containerv1beta1.NodeTaint
	var spot bool

	if !g.ClusterContext.ForceOnDemand {
		if resName, ok := p.Spec.NodeSelector["cloud.google.com/reservation-name"]; ok {
			var resVal string
			resProj, ok := p.Spec.NodeSelector["cloud.google.com/reservation-project"]
			if ok {
				resVal = fmt.Sprintf("projects/%s/reservations/%s", resProj, resName)
			} else {
				resVal = resName
			}
			reservation = &containerv1beta1.ReservationAffinity{
				ConsumeReservationType: "SPECIFIC_RESERVATION",
				Key:                    "compute.googleapis.com/reservation-name",
				Values: []string{
					resVal,
				},
			}
		}

		spot = p.Spec.NodeSelector["cloud.google.com/gke-spot"] == "true"
		if spot {
			// Add the taint that NAP would add.
			// https://cloud.google.com/kubernetes-engine/docs/concepts/spot-vms#spotvms-nap
			taints = append(taints, &containerv1beta1.NodeTaint{
				Key:    "cloud.google.com/gke-spot",
				Value:  "true",
				Effect: "NO_SCHEDULE",
			})
		}
	}

	var secondaryDisks []*containerv1beta1.SecondaryBootDisk
	if g.ClusterContext.NodeSecondaryDisk != "" {
		secondaryDisks = []*containerv1beta1.SecondaryBootDisk{
			{
				// Example: "projects/my-gcp-project/global/images/my-disk-image"
				DiskImage: g.ClusterContext.NodeSecondaryDisk,
				Mode:      "CONTAINER_IMAGE_CACHE",
			},
		}
	}

	var networkConfig *containerv1beta1.NodeNetworkConfig
	var additionalNodeNetworks []*containerv1beta1.AdditionalNodeNetworkConfig
	// additional-node-networks: "vpc1:subnet1, vpc2:subnet2"
	additionalNodeNetworksCSV := g.ClusterContext.NodeAdditionalNetworks
	if getAnnotation(p, AnnotationAdditionalNodeNetworks) != "" {
		additionalNodeNetworksCSV = getAnnotation(p, AnnotationAdditionalNodeNetworks)
	}
	for _, pair := range strings.Split(additionalNodeNetworksCSV, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}

		netAndSubnet := strings.SplitN(pair, ":", 2)
		if len(netAndSubnet) != 2 {
			return nil, fmt.Errorf("invalid additional network annotation: %v", pair)
		}

		additionalNodeNetworks = append(additionalNodeNetworks, &containerv1beta1.AdditionalNodeNetworkConfig{
			Network:    strings.TrimSpace(netAndSubnet[0]),
			Subnetwork: strings.TrimSpace(netAndSubnet[1]),
		})
	}
	if len(additionalNodeNetworks) > 0 {
		networkConfig = &containerv1beta1.NodeNetworkConfig{
			AdditionalNodeNetworkConfigs: additionalNodeNetworks,
		}
	}

	nodeServiceAccount := g.ClusterContext.NodeServiceAccount
	if sa, ok := p.Annotations[AnnotationNodeServiceAccount]; ok {
		nodeServiceAccount = sa
	}

	return &containerv1beta1.NodePool{
		Name: name,
		Config: &containerv1beta1.NodeConfig{
			ServiceAccount: nodeServiceAccount,
			ShieldedInstanceConfig: &containerv1beta1.ShieldedInstanceConfig{
				EnableIntegrityMonitoring: true,
				EnableSecureBoot:          g.ClusterContext.NodeSecureBoot,
			},
			Tags: g.ClusterContext.NodeTags,
			// NOTE: vendor/ was manually updated to include the field because
			// it was not currently available at the time of writing:
			SecondaryBootDisks:  secondaryDisks,
			MachineType:         machineType,
			ReservationAffinity: reservation,
			Labels:              labels,
			Spot:                spot,
			Taints:              taints,
		},
		InitialNodeCount: int64(nodeCount),
		Locations:        []string{g.ClusterContext.NodeZone},
		PlacementPolicy: &containerv1beta1.PlacementPolicy{
			TpuTopology: tpuTopo,
			Type:        "COMPACT",
		},
		Management: &containerv1beta1.NodeManagement{
			AutoRepair:  true,
			AutoUpgrade: false,
		},
		UpgradeSettings: &containerv1beta1.UpgradeSettings{
			MaxSurge: 1,
		},
		MaxPodsConstraint: &containerv1beta1.MaxPodsConstraint{MaxPodsPerNode: maxPodsPerNode},
		NetworkConfig:     networkConfig,
	}, nil
}

func sumTPURequests(p *corev1.Pod) (int, error) {
	var n int
	for _, c := range p.Spec.Containers {
		if c.Resources.Requests == nil {
			continue
		}
		req, ok := c.Resources.Requests[corev1.ResourceName(GoogleTPUResource)]
		if !ok {
			continue
		}
		v, ok := req.AsInt64()
		if !ok {
			return 0, fmt.Errorf(("invalid TPU request: %v"), req.String())
		}
		n += int(v)
	}
	return n, nil
}

// podToNodePoolName deterministically generates a node pool name for a given pod,
// by using the JobSet name and job-key (SHA1 hash of namespaced job key), as
// given in the pod labels.
// These labels are stable through JobSet restarts, so the node pool name
// generated here will be the same if the JobSet is restarted.
// Node pool name format is: {first 34 chars of jobset name}-{first 5 chars of job-key}
// This ensures node pool names are within the 40 char limit on node pool name size.
func podToNodePoolName(p *corev1.Pod) (string, error) {
	jobSetName, exists := p.Labels[jobset.JobSetNameKey]
	if !exists {
		return "", fmt.Errorf("%s label not found on pod %s", jobset.JobSetNameKey, p.Name)
	}
	jobKey, exists := p.Labels[jobset.JobKey]
	if !exists {
		return "", fmt.Errorf("%s label not found on pod %s", jobset.JobKey, p.Name)
	}

	prefixLength := min(maxJobSetPrefixLength, len(jobSetName))
	prefix := jobSetName[:prefixLength]
	suffix := jobKey[:jobKeySuffixLength]
	nodePoolName := fmt.Sprintf("%s-%s", prefix, suffix)
	return nodePoolName, nil
}

func tpuTopologyToNodeCount(accelerator, topo string) (int, error) {
	var expectedDims int
	switch accelerator {
	case V4PodSliceAccelerator, V5pPodSliceAccelerator:
		expectedDims = 3
	case V5ePodSliceAccelerator, V6eSliceAccelerator:
		expectedDims = 2
	default:
		return 0, fmt.Errorf("invalid accelerator: %v", accelerator)
	}

	split := strings.Split(topo, "x")
	if len(split) != expectedDims {
		return 0, fmt.Errorf("invalid topology: %v, expected %v dimensions", topo, expectedDims)
	}

	product := 1
	for _, s := range split {
		x, err := strconv.Atoi(s)
		if err != nil {
			return 0, fmt.Errorf("invalid topology: %v, could not convert %q to int: %w", topo, s, err)
		}
		product *= x
	}

	return product / 4, nil
}

// tpuMachineType takes an accelerator type (from nodeSelector) and a TPU request
// from container requests and returns the corresponding machine type.
func tpuMachineType(accel string, tpuRequest int) (string, error) {
	if tpuRequest < 1 {
		return "", fmt.Errorf("invalid TPU request: %v", tpuRequest)
	}

	switch accel {
	case V4PodSliceAccelerator: // v4
		return fmt.Sprintf("ct4p-hightpu-%vt", tpuRequest), nil
	case V5ePodSliceAccelerator: // v5e
		return fmt.Sprintf("ct5lp-hightpu-%vt", tpuRequest), nil
	case V5pPodSliceAccelerator: // v5p
		return fmt.Sprintf("ct5p-hightpu-%vt", tpuRequest), nil
	case V6eSliceAccelerator: // v6e
		return fmt.Sprintf("ct6e-standard-%vt", tpuRequest), nil
	}

	return "", fmt.Errorf("invalid accelerator: %v", accel)
}

func waitForGkeOp(svc *containerv1beta1.Service, c GKEContext, operation *containerv1beta1.Operation) error {
	operationWaitTimeout := 30 * time.Minute
	operationPollInterval := 5 * time.Second

	for start := time.Now(); time.Since(start) < operationWaitTimeout; time.Sleep(operationPollInterval) {
		if op, err := svc.Projects.Locations.Operations.Get(c.OpName(operation.Name)).Do(); err == nil {
			if op.Status == "DONE" {
				return nil
			}
		} else {
			return fmt.Errorf("waiting for operation: %w", err)
		}
	}

	return fmt.Errorf("timeout while waiting for operation %s on %s to complete", operation.Name, operation.TargetLink)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func getAnnotation(p *corev1.Pod, key string) string {
	if p.Annotations == nil {
		return ""
	}
	return p.Annotations[key]
}
