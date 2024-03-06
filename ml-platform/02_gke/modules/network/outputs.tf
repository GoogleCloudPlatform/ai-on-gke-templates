# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

output "vpc" {
  value       = google_compute_network.vpc-network.id
  description = "VPC."
}

output "subnet-1" {
  value       = google_compute_subnetwork.subnet-1.id
  description = "subnet1."
}

output "subnet-2" {
  value       = google_compute_subnetwork.subnet-2.id
  description = "subnet2."
}
