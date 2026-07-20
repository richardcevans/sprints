# Traceability

## Inputs

* User request: create a sprint tutorial for configuring OCI Full Stack DR with Windows machines joined to Active Directory, using special tags so drill-created machines use a different standby subnet and different Network Security Groups.
* User-provided tag pattern: `FullStackDRDrill_<REGION_KEY>_SubnetId`, `FullStackDRDrill_<REGION_KEY>_NSGId1`, and `FullStackDRDrill_<REGION_KEY>_NSGId2`, with examples for IAD and PHX.
* User clarification: the alternate subnet and NSG tag behavior is available only for DR Drill.
* User clarification: the standard VNIC mapping configured when adding the instance to Full Stack DR is still required and is used for failover and switchover.
* Local repository pattern: `oci/sprint-create-fsdr-resource-modifiers-oke`.

## External References Checked

* Oracle documentation: Add a moving instance to a Disaster Recovery Protection Group.
* Oracle documentation: Preparing compute instances for Full Stack Disaster Recovery.
* Oracle documentation: Disaster recovery for OCI Compute instances.
* Oracle documentation: Resource principal policy examples for OCI Full Stack DR.
* Oracle SDK documentation: `ComputeInstanceMovableVnicMappingDetails`, including `destinationSubnetId` and `destinationNsgIdList`.
* Oracle Terraform provider documentation: `oci_disaster_recovery_dr_protection_group` moving-instance VNIC mapping fields.

## Claims Mapped to Sources

* Moving-instance members require source VNIC to destination subnet mapping: Oracle Full Stack DR moving-instance documentation and SDK model.
* Destination NSGs can be configured for a moving-instance VNIC mapping: Oracle Full Stack DR moving-instance documentation and SDK/Terraform model.
* Compute instances require Full Stack DR preparation, including volume group and related DR prerequisites: Oracle Full Stack DR compute preparation documentation.
* Full Stack DR uses IAM policies and resource-principal access for managed resources: Oracle Full Stack DR policy and resource-principal documentation.

## Claims From SME Input

* A Windows drill instance joined to the same Active Directory as production can create duplicate machine identity risk when it uses the same Windows computer name and NetBIOS identity.
* Isolating the standby subnet from Active Directory is the desired sandbox control for drills.
* Tags named `FullStackDRDrill_<REGION_KEY>_SubnetId`, `FullStackDRDrill_<REGION_KEY>_NSGId1`, and `FullStackDRDrill_<REGION_KEY>_NSGId2` are required on the source machine to drive alternate subnet and NSG placement for DR Drill.
* The region key in the tag name must match the target drill region, such as `IAD` or `PHX`.
* The alternate subnet and NSG tag behavior applies only to DR Drill.
* The standard Full Stack DR VNIC mapping must still be configured for the moving instance and remains the mapping for failover and switchover.

## Pending Confirmation

* Whether the final environment stores these keys as free-form tags or defined tags.
* Whether final screenshots should show the current OCI Console source instance tag page, DRPG member page, or both.
