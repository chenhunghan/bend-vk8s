import Base
import ../src/net/cidr.bend as C

def Laws.cidr.ip.go(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{x}:
      x
    case None{}:
      0

# Spec for src/net/cidr.bend: vcluster pkg/util/servicecidr
# TestDetectPrefix, the IPv4 cases (servicecidr_test.go), each with
# isInRange = the test's net.IPNet Contains.

def Laws.cidr.ip(+s: String) -> U32:
  Laws.cidr.ip.go(C.Cidr.parse_ip(s))

# "simple 1"
law cidr.simple1:
  {C.Cidr.detect(Laws.cidr.ip("192.168.194.208"), Laws.cidr.ip("192.168.194.128"), 25) == "192.168.194.128/25" : String}

# "simple 2"
law cidr.simple2:
  {C.Cidr.detect(Laws.cidr.ip("192.168.1.5"), Laws.cidr.ip("192.168.1.0"), 24) == "192.168.1.0/24" : String}

# "simple 3"
law cidr.simple3:
  {C.Cidr.detect(Laws.cidr.ip("10.0.0.128"), Laws.cidr.ip("10.0.0.128"), 25) == "10.0.0.128/25" : String}

# "simple 4"
law cidr.simple4:
  {C.Cidr.detect(Laws.cidr.ip("172.16.5.33"), Laws.cidr.ip("172.16.5.32"), 27) == "172.16.5.32/27" : String}

# "simple 5"
law cidr.simple5:
  {C.Cidr.detect(Laws.cidr.ip("192.168.194.225"), Laws.cidr.ip("192.168.194.128"), 25) == "192.168.194.128/25" : String}

# A vk8s host cluster's default range.
law cidr.vk8s_default:
  {C.Cidr.detect(Laws.cidr.ip("10.96.12.34"), Laws.cidr.ip("10.96.0.0"), 12) == "10.96.0.0/12" : String}

law cidr.parse_bad:
  {C.Cidr.parse_ip("10.96.0.256") == None{} : Maybe<&2, U32>}
