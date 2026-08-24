# D2 diagram alternatives

A [D2](https://d2lang.com) version of the Wiring/Network diagrams in `README.md`'s
Architecture section, for side-by-side comparison. Nothing in `README.md` or the existing
`.drawio`/`.drawio.svg` files was changed.

Preview these blocks at [play.d2lang.com](https://play.d2lang.com) (paste the contents of a
block in), with the [D2 VS Code extension](https://marketplace.visualstudio.com/items?itemName=terrastruct.d2),
or via the `d2` CLI if installed.

### Wiring
```d2
direction: right

"node1": {
  shape: rectangle
  style.fill: "#f8cecc"
  style.stroke: "#b85450"
}
"node1-vm": "VM" {
  style.fill: "#d5e8d4"
  style.stroke: "#82b366"
}

"node2": {
  shape: rectangle
  style.fill: "#f8cecc"
  style.stroke: "#b85450"
}
"node2-vm": "VM" {
  style.fill: "#d5e8d4"
  style.stroke: "#82b366"
}

"k8s": "K8S" {
  shape: rectangle
  style.fill: "#dae8fc"
  style.stroke: "#6c8ebf"
}

"oob-switch": "out-of-band-switch" {
  shape: rectangle
  style.fill: "#f8cecc"
  style.stroke: "#b85450"
}

"ib-switch": "in-band-switch" {
  shape: rectangle
  style.fill: "#d5e8d4"
  style.stroke: "#82b366"
}

"node1" -> "node1-vm": "eth2 <-> eth1" {
  style.stroke: "#82b366"
}
"node2" -> "node2-vm": "eth2 <-> eth1" {
  style.stroke: "#82b366"
}

"node1" -> "oob-switch": "eth1 <-> eth2" {
  style.stroke: "#b85450"
}
"node2" -> "oob-switch": "eth1 <-> eth3" {
  style.stroke: "#b85450"
}
"k8s" -> "oob-switch": "eth1 <-> eth4" {
  style.stroke: "#b85450"
}
"node1" -> "ib-switch": "eth2 <-> eth2" {
  style.stroke: "#82b366"
}
"node2" -> "ib-switch": "eth2 <-> eth3" {
  style.stroke: "#82b366"
}
"k8s" -> "ib-switch": "eth2 <-> eth4" {
  style.stroke: "#82b366"
}
```

### Network
```d2
direction: down

"oob-network": "Out-of-Band Network\n172.16.100.0/24" {
  shape: rectangle
  style.fill: "#f8cecc"
  style.stroke: "#b85450"
}

"ib-network": "In-Band Network\n10.250.200.0/24" {
  shape: rectangle
  style.fill: "#d5e8d4"
  style.stroke: "#82b366"
}

"node1-bmc": "node1 BMC" {
  style.fill: "#f8cecc"
  style.stroke: "#b85450"
}
"node2-bmc": "node2 BMC" {
  style.fill: "#f8cecc"
  style.stroke: "#b85450"
}
"node1-vm": "node1 VM" {
  style.fill: "#d5e8d4"
  style.stroke: "#82b366"
}
"node2-vm": "node2 VM" {
  style.fill: "#d5e8d4"
  style.stroke: "#82b366"
}
"k8s": "K8S" {
  style.fill: "#dae8fc"
  style.stroke: "#6c8ebf"
}

"node1-bmc" -> "oob-network": ".11" { style.stroke: "#b85450" }
"node2-bmc" -> "oob-network": ".12" { style.stroke: "#b85450" }
"k8s" -> "oob-network": ".2" { style.stroke: "#b85450" }
"node1-vm" -> "ib-network": ".11" { style.stroke: "#82b366" }
"node2-vm" -> "ib-network": ".12" { style.stroke: "#82b366" }
"k8s" -> "ib-network": ".2" { style.stroke: "#82b366" }
```
