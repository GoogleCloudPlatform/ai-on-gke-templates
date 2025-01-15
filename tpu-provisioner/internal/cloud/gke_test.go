package cloud

import (
	"fmt"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/google/go-cmp/cmp"
	container "google.golang.org/api/container/v1beta1"
	containerv1beta1 "google.golang.org/api/container/v1beta1"
	v1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	jobset "sigs.k8s.io/jobset/api/jobset/v1alpha2"
)

func Test_tpuTopologyToNodeCount(t *testing.T) {
	cases := []struct {
		accel string
		topo  string
		count int
		err   bool
	}{
		{
			accel: "tpu-v4-podslice",
			topo:  "2x2x1",
			count: 1,
		},
		{
			accel: "tpu-v4-podslice",
			topo:  "2x2x2",
			count: 2,
		},
		{
			accel: "tpu-v5p-slice",
			topo:  "2x2x2",
			count: 2,
		},
		{
			accel: "tpu-v4-podslice",
			topo:  "2x2x4",
			count: 4,
		},
		{
			accel: "tpu-v5p-slice",
			topo:  "2x2x4",
			count: 4,
		},
		{
			accel: "tpu-v4-podslice",
			topo:  "2x4x4",
			count: 8,
		},
		{
			accel: "tpu-v5-lite-podslice",
			topo:  "2x4",
			count: 2,
		},
		{
			accel: "not-an-accel",
			topo:  "2x4",
			err:   true,
		},
		{
			accel: "tpu-v4-podslice",
			topo:  "not-a-topo",
			err:   true,
		},
		{
			accel: "tpu-v6e-slice",
			topo:  "16x16",
			count: 64,
		},
		{
			accel: "tpu-v6e-slice",
			topo:  "1x1x1",
			err:   true,
		},
	}

	for _, c := range cases {
		t.Run(c.accel+"_"+c.topo, func(t *testing.T) {
			count, err := tpuTopologyToNodeCount(c.accel, c.topo)
			if (err != nil) != c.err {
				t.Fatalf("error: expected: %v", c.err)
			}
			if exp, got := c.count, count; exp != got {
				t.Fatalf("count: expected: %v, got: %v", exp, got)
			}
		})
	}
}

func Test_tpuMachineType(t *testing.T) {
	cases := []struct {
		accel       string
		tpuRequest  int
		machineType string
		err         bool
	}{
		{
			accel:       "tpu-v4-podslice",
			tpuRequest:  4,
			machineType: "ct4p-hightpu-4t",
		},
		{
			accel:       "tpu-v5-lite-podslice",
			tpuRequest:  1,
			machineType: "ct5lp-hightpu-1t",
		},
		{
			accel:       "tpu-v5-lite-podslice",
			tpuRequest:  4,
			machineType: "ct5lp-hightpu-4t",
		},
		{
			accel:       "tpu-v5-lite-podslice",
			tpuRequest:  8,
			machineType: "ct5lp-hightpu-8t",
		},
		{
			accel:       "tpu-v5p-slice",
			tpuRequest:  4,
			machineType: "ct5p-hightpu-4t",
		},
		{
			accel:      "not-an-accel",
			tpuRequest: 4,
			err:        true,
		},
		{
			accel:      "tpu-v5p-slice",
			tpuRequest: -1,
			err:        true,
		},
	}

	for _, c := range cases {
		t.Run(fmt.Sprintf("%v_accel_%v_tpus", c.accel, c.tpuRequest), func(t *testing.T) {
			machineType, err := tpuMachineType(c.accel, c.tpuRequest)
			if (err != nil) != c.err {
				t.Fatalf("error: expected: %v", c.err)
			}
			if exp, got := c.machineType, machineType; exp != got {
				t.Fatalf("machineType: expected: %v, got: %v", exp, got)
			}
		})
	}
}

func TestPodToNodePoolName(t *testing.T) {
	var jobKey = "759730a97e4373f3a0ee12805db065e3a4a649a5"

	testCases := []struct {
		name          string
		pod           *corev1.Pod
		expectedName  string
		expectedError bool
	}{
		{
			name: "Missing JobSetName label",
			pod: &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test-pod",
					Labels: map[string]string{
						jobset.JobKey: jobKey,
					},
				},
			},
			expectedError: true,
		},
		{
			name: "Missing JobKey label",
			pod: &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test-pod",
					Labels: map[string]string{
						jobset.JobSetNameKey: "some-job-set-name",
					},
				},
			},
			expectedError: true,
		},
		{
			name: "jobset name less than 34 chars",
			pod: &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test-pod",
					Labels: map[string]string{
						jobset.JobSetNameKey: "myjobset",
						jobset.JobKey:        jobKey,
					},
				},
			},
			expectedName: fmt.Sprintf("myjobset-%s", jobKey[:jobKeySuffixLength]),
		},
		{
			name: "jobset name more than 34 chars",
			pod: &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test-pod",
					Labels: map[string]string{
						jobset.JobSetNameKey: "myjobset-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
						jobset.JobKey:        jobKey,
					},
				},
			},
			expectedName: fmt.Sprintf("%s-%s", "myjobset-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"[:maxJobSetPrefixLength], jobKey[:jobKeySuffixLength]),
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result, err := podToNodePoolName(tc.pod)

			if tc.expectedError && err == nil {
				t.Errorf("Expected error but got none")
			}
			if !tc.expectedError && err != nil {
				t.Errorf("Unexpected error: %v", err)
			}
			if result != tc.expectedName {
				t.Errorf("Expected node pool name %s, got %s", tc.expectedName, result)
			}
		})
	}
}

func TestNodePoolForPod(t *testing.T) {
	trueVar := true
	tests := []struct {
		desc                  string
		gkeContext            GKEContext
		additionalLabels      map[string]string
		additionalAnnotations map[string]string
		selector              map[string]string
		want                  *containerv1beta1.NodePool
	}{
		{
			desc: "simple case",
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc: "spot",
			selector: map[string]string{
				"cloud.google.com/gke-spot": "true",
			},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
					Spot:                   true,
					Taints: []*container.NodeTaint{
						{Effect: "NO_SCHEDULE", Key: "cloud.google.com/gke-spot", Value: "true"},
					},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc:       "spot with forced on demand",
			gkeContext: GKEContext{ForceOnDemand: true},
			selector: map[string]string{
				"cloud.google.com/gke-spot": "true",
			},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
					Spot:                   false,
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc:     "pod with reservation selector",
			selector: map[string]string{"cloud.google.com/reservation-name": "tpu-rsv"},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType: "ct5p-hightpu-4t",
					ReservationAffinity: &container.ReservationAffinity{
						ConsumeReservationType: "SPECIFIC_RESERVATION",
						Key:                    "compute.googleapis.com/reservation-name",
						Values:                 []string{"tpu-rsv"},
					},
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc: "pod with cross-project reservation selector",
			selector: map[string]string{
				"cloud.google.com/reservation-name":    "tpu-rsv",
				"cloud.google.com/reservation-project": "tpu-rsv-project",
			},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType: "ct5p-hightpu-4t",
					ReservationAffinity: &container.ReservationAffinity{
						ConsumeReservationType: "SPECIFIC_RESERVATION",
						Key:                    "compute.googleapis.com/reservation-name",
						Values:                 []string{"projects/tpu-rsv-project/reservations/tpu-rsv"},
					},
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc:       "pod with reservation selector but on demand is forced",
			selector:   map[string]string{"cloud.google.com/reservation-name": "tpu-rsv"},
			gkeContext: GKEContext{ForceOnDemand: true},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType:            "ct5p-hightpu-4t",
					ReservationAffinity:    nil,
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc:     "pod with disabling ICI resiliency selector",
			selector: map[string]string{"cloud.google.com/gke-tpu-ici-resiliency": "false"},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
						"cloud.google.com/gke-tpu-ici-resiliency":     "false",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc:       "pod with secondary boot disk",
			gkeContext: GKEContext{NodeSecondaryDisk: "projects/my-gcp-project/global/images/my-disk-image"},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
					SecondaryBootDisks: []*containerv1beta1.SecondaryBootDisk{
						{
							DiskImage: "projects/my-gcp-project/global/images/my-disk-image",
							Mode:      "CONTAINER_IMAGE_CACHE",
						},
					},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc:     "pod with location hint node selector",
			selector: map[string]string{"cloud.google.com/gke-location-hint": "test-location-hint"},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
						"cloud.google.com/gke-location-hint":          "test-location-hint",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc: "labels to copy from pod to node",
			gkeContext: GKEContext{
				PodToNodeLabels: []string{"should-be-copied"},
			},
			additionalLabels: map[string]string{
				"should-be-copied":     "val-a",
				"should-not-be-copied": "val-b",
			},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
						"should-be-copied":                            "val-a",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc: "labels to copy from pod to node by annotation",
			additionalLabels: map[string]string{
				"copy-me":      "val-x",
				"dont-copy-me": "val-y",
			},
			additionalAnnotations: map[string]string{
				"tpu-provisioner.cloud.google.com/copy-labels": "copy-me",
			},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
						"copy-me": "val-x",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
			},
		},
		{
			desc: "additional node networks configured in cluster context",
			gkeContext: GKEContext{
				NodeAdditionalNetworks: "network-1:subnet-1, network-2:subnet-2",
			},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
				NetworkConfig: &container.NodeNetworkConfig{
					AdditionalNodeNetworkConfigs: []*container.AdditionalNodeNetworkConfig{
						{
							Network:    "network-1",
							Subnetwork: "subnet-1",
						},
						{
							Network:    "network-2",
							Subnetwork: "subnet-2",
						},
					},
				},
			},
		},
		{
			desc: "pod requesting additional node networks",
			gkeContext: GKEContext{
				NodeAdditionalNetworks: "should-be-overriden-1:should-be-overriden-2",
			},
			additionalAnnotations: map[string]string{
				"tpu-provisioner.cloud.google.com/additional-node-networks": "network-1:subnet-1, network-2:subnet-2",
			},
			want: &containerv1beta1.NodePool{
				Config: &container.NodeConfig{
					Labels: map[string]string{
						"google.com/nodepool-manager":                 "tpu-provisioner",
						"google.com/tpu-provisioner-jobset-name":      "jobset-test",
						"google.com/tpu-provisioner-jobset-namespace": "default",
						"google.com/tpu-provisioner-parent-kind":      "job",
						"google.com/tpu-provisioner-parent-name":      "jobset-test-job-1-0",
						"google.com/tpu-provisioner-parent-namespace": "default",
					},
					MachineType:            "ct5p-hightpu-4t",
					ShieldedInstanceConfig: &container.ShieldedInstanceConfig{EnableIntegrityMonitoring: true},
				},
				InitialNodeCount:  512,
				Locations:         []string{""},
				Management:        &container.NodeManagement{AutoRepair: true, AutoUpgrade: false},
				MaxPodsConstraint: &container.MaxPodsConstraint{MaxPodsPerNode: 15},
				Name:              "test-pool",
				PlacementPolicy:   &container.PlacementPolicy{TpuTopology: "8x16x16", Type: "COMPACT"},
				UpgradeSettings:   &container.UpgradeSettings{MaxSurge: 1},
				NetworkConfig: &container.NodeNetworkConfig{
					AdditionalNodeNetworkConfigs: []*container.AdditionalNodeNetworkConfig{
						{
							Network:    "network-1",
							Subnetwork: "subnet-1",
						},
						{
							Network:    "network-2",
							Subnetwork: "subnet-2",
						},
					},
				},
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.desc, func(t *testing.T) {
			gke := &GKE{
				ClusterContext: tc.gkeContext,
			}

			labels := map[string]string{
				"batch.kubernetes.io/controller-uid":        "8484279a-de52-4ca1-b01e-130fbded30fb",
				"batch.kubernetes.io/job-name":              "jobset-test-job-1-0",
				"controller-uid":                            "8484279a-de52-4ca1-b01e-130fbded30fb",
				"job-name":                                  "jobset-test-job-1-0",
				"jobset.sigs.k8s.io/job-index":              "0",
				"jobset.sigs.k8s.io/job-key":                "random-key",
				"jobset.sigs.k8s.io/jobset-name":            "jobset-test",
				"jobset.sigs.k8s.io/replicatedjob-name":     "job-1",
				"jobset.sigs.k8s.io/replicatedjob-replicas": "1",
				"jobset.sigs.k8s.io/restart-attempt":        "0",
			}
			for k, v := range tc.additionalLabels {
				labels[k] = v
			}

			annotations := map[string]string{
				"alpha.jobset.sigs.k8s.io/exclusive-topology": "cloud.google.com/gke-nodepool",
				"batch.kubernetes.io/job-completion-index":    "0",
				"jobset.sigs.k8s.io/job-index":                "0",
				"jobset.sigs.k8s.io/job-key":                  "random-key",
				"jobset.sigs.k8s.io/jobset-name":              "jobset-test",
				"jobset.sigs.k8s.io/replicatedjob-name":       "job-1",
				"jobset.sigs.k8s.io/replicatedjob-replicas":   "1",
				"jobset.sigs.k8s.io/restart-attempt":          "0",
			}
			for k, v := range tc.additionalAnnotations {
				annotations[k] = v
			}

			pod := &v1.Pod{
				TypeMeta: metav1.TypeMeta{
					APIVersion: "v1",
					Kind:       "Pod",
				},
				ObjectMeta: metav1.ObjectMeta{
					Annotations: annotations,
					Labels:      labels,
					Finalizers:  []string{"batch.kubernetes.io/job-tracking"},
					Name:        "job-test-6gfwq",
					Namespace:   "default",
					OwnerReferences: []metav1.OwnerReference{
						{
							APIVersion:         "batch/v1",
							Kind:               "Job",
							UID:                "8484279a-de52-4ca1-b01e-130fbded30fb",
							Name:               "jobset-test-job-1-0",
							Controller:         &trueVar,
							BlockOwnerDeletion: &trueVar,
						},
					},
					GenerateName:    "jobset-test-job-1-0-0-",
					ResourceVersion: "70731715",
					UID:             "f6a99195-268e-4b68-91de-22e75f9100bc",
				},
				Spec: v1.PodSpec{
					NodeSelector: map[string]string{
						"cloud.google.com/gke-tpu-accelerator": "tpu-v5p-slice",
						"cloud.google.com/gke-tpu-topology":    "8x16x16",
					},
					Containers: []v1.Container{
						{
							Resources: v1.ResourceRequirements{
								Requests: v1.ResourceList{
									"google.com/tpu": resource.MustParse("4"),
								},
								Limits: v1.ResourceList{
									"google.com/tpu": resource.MustParse("4"),
								},
							},
						},
					},
				},
			}
			if tc.selector != nil {
				for k, v := range tc.selector {
					pod.Spec.NodeSelector[k] = v
				}
			}
			got, err := gke.nodePoolForPod("test-pool", pod)
			if err != nil {
				t.Errorf("Got error: %v", err)
			}
			if diff := cmp.Diff(tc.want, got); diff != "" {
				t.Errorf("TestNodePoolForPod() return unexpected node pool, diff (-want +got): \n%s", diff)
			}
		})
	}
}
