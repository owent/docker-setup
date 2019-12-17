# README for router

## nftables Hook

|  Type  |       Families          |      Hooks                             |        Description                                     |
|--------|-------------------------|----------------------------------------|--------------------------------------------------------|
| filter | all                     | all                                    | Standard chain type to use in doubt.                   |
| nat    | ip, ip6, inet           | prerouting, input, output, postrouting | Chains of this type perform Native Address Translation based on conntrack entries. Only the first packet of a connection actually traverses this chain - its rules usually define details of the created conntrack entry (NAT statements for instance). |
| route  | ip, ip6                 | output                                 | If a packet has traversed a chain of this type and is about to be accepted, a new route lookup is performed if relevant parts of the IP header have changed. This allows to e.g. implement policy routing selectors in nftables. |

## Standard priority names, family and hook compatibility matrix

> The priority parameter accepts a signed integer value or a standard priority name which specifies the order in which chains with same hook value are traversed. The ordering is ascending, i.e. lower priority values have precedence over higher ones.

| Name      | Value | Families                   | Hooks       |
|-----------|-------|----------------------------|-------------|
| raw       | -300  | ip, ip6, inet              | all         |
| mangle    | -150  | ip, ip6, inet              | all         |
| dstnat    | -100  | ip, ip6, inet              | prerouting  |
| filter    | 0     | ip, ip6, inet, arp, netdev | all         |
| security  | 50    | ip, ip6, inet              | all         |
| srcnat    | 100   | ip, ip6, inet              | postrouting |

## Standard priority names and hook compatibility for the bridge family

|Name   | Value | Hooks       |
|-------|-------|-------------|
|dstnat | -300  | prerouting  |
|filter | -200  | all         |
|out    | 100   | output      |
|srcnat | 300   | postrouting |
