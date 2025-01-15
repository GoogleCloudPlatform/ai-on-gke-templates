package cloud

import "fmt"

type GKEContext struct {
	ProjectID              string
	ClusterLocation        string
	Cluster                string
	NodeZone               string
	NodeServiceAccount     string
	NodeAdditionalNetworks string
	NodeSecondaryDisk      string
	NodeTags               []string
	// PodToNodeLabels is a list of key=value pairs that will be copied from the Pod
	// to the Node.
	PodToNodeLabels []string
	NodeSecureBoot  bool
	ForceOnDemand   bool
}

func (c GKEContext) ClusterName() string {
	return fmt.Sprintf("projects/%v/locations/%v/clusters/%v",
		c.ProjectID,
		c.ClusterLocation,
		c.Cluster,
	)
}

func (c GKEContext) NodePoolName(name string) string {
	return fmt.Sprintf("projects/%v/locations/%v/clusters/%v/nodePools/%v",
		c.ProjectID,
		c.ClusterLocation,
		c.Cluster,
		name,
	)
}

func (c GKEContext) OpName(op string) string {
	return fmt.Sprintf("projects/%v/locations/%v/operations/%v",
		c.ProjectID,
		c.ClusterLocation,
		op,
	)
}
