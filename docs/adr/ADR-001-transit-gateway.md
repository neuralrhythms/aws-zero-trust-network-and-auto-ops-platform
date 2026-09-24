# ADR-001: AWS Transit Gateway over VPC Peering

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

The platform spans eight AWS accounts across three Organisational Units. Workload VPCs must route all egress traffic through a centralised inspection point (Network Firewall + NAT Gateway) in the `network-hub` account. The connectivity model must support adding new spoke VPCs without changes to existing VPCs, enforce symmetric routing through the firewall, and remain operationally manageable as the number of accounts grows.

Two options were evaluated:

| Criterion | VPC Peering | AWS Transit Gateway |
|-----------|-------------|---------------------|
| Scalability | O(n²) peering connections required | Single hub; spokes attach independently |
| Centralised inspection | Requires complex routing workarounds | Native via TGW route tables |
| Transitive routing | Not supported | Supported |
| Operational overhead | High — each new account needs n new peerings | Low — one attachment per new account |
| Cost model | Free data transfer (same region) | Per-attachment + per-GB data charge |

---

## Decision

Use **AWS Transit Gateway** as the hub-spoke connectivity fabric. Each workload VPC attaches via a dedicated `/28` `tgw-attach` subnet tier (one subnet per Availability Zone). Separate TGW route tables for spoke VPCs and the inspection VPC enforce symmetric routing: all spoke egress routes to the Network Firewall, and return traffic traverses the same firewall endpoint.

---

## Consequences

**Positive:** Adding a new spoke account requires one TGW attachment and one route table association — no changes to existing VPCs or route tables. Symmetric routing is structurally enforced, eliminating asymmetric firewall bypass. VPC Flow Logs at the `/28` attachment subnet capture all inter-VPC traffic at the precise attachment point.

**Negative:** TGW incurs a per-attachment hourly charge and per-GB data processing fee. The `/28` per-AZ subnet requirement consumes a small CIDR block from each spoke VPC's address space. At the current scale (four workload accounts) the cost difference from VPC peering is modest.

**Risk mitigated:** The dedicated `tgw-attach` subnet isolates TGW route propagation from workload route tables, containing the blast radius of any route misconfiguration to the attachment subnet only.
