# Workshop Details

## Mode

How-to-guide

## Target Duration

60 minutes

## Lab Count

One sprint tutorial with six task sections.

## Short Description

Configure OCI Full Stack DR so Windows Active Directory joined moving instances keep standard VNIC mappings for failover and switchover, while using region-specific alternate subnet and NSG tags during DR Drills.

## Long Description

This sprint teaches administrators how to protect Windows compute instances joined to Active Directory with OCI Full Stack Disaster Recovery while keeping DR Drills safe. Learners configure the standard moving-instance VNIC mapping for failover and switchover, prepare alternate drill subnets with no Active Directory connectivity, add region-specific `FullStackDRDrill_<REGION_KEY>_SubnetId`, `FullStackDRDrill_<REGION_KEY>_NSGId1`, and `FullStackDRDrill_<REGION_KEY>_NSGId2` tags to the source machine in the OCI Console, refresh and verify plans, run a drill, and validate that the recovered Windows instance cannot reach domain controllers.

## Audience

* OCI administrators
* Windows administrators
* Disaster recovery operators
* Application owners responsible for domain-joined Windows workloads

## Prerequisites

* OCI Full Stack DR protection groups associated across primary and standby regions.
* Windows compute instance joined to Active Directory.
* Standby VCN and sandbox subnet.
* Standby NSG or NSGs for drill isolation.
* Permissions to manage compute, networking, tags, DR protection groups, and DR plans.

## Workshop Outline

1. Review the Active Directory duplicate identity risk.
2. Prepare the standby sandbox subnet and NSGs.
3. Apply DR Drill alternate subnet and NSG tags to the source Windows instance.
4. Configure the standard Full Stack DR VNIC mapping for failover and switchover.
5. Refresh, verify, and run a drill.
6. Operationalize the pattern.

## SME Gaps

* Confirm whether the target deployment stores the `FullStackDRDrill_<REGION_KEY>_*` keys as free-form tags or defined tags.
* Confirm the final screenshots for the source instance tag page and DR Drill execution.
* Confirm the final standard recovery subnet and NSG design for switchover and failover.

## FreeSQL Summary

No FreeSQL content is used. This sprint covers OCI networking, tags, Full Stack DR moving-instance mappings, and Windows PowerShell validation.
