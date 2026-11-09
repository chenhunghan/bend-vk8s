import Base
import ../laws/endpoint.bend as L
import ../src/translate/endpoint.bend as E

# Proofs of laws/endpoint.bend: `def L.<law>` for each law.
#
# The concrete laws compute. The general laws compute too: the standalone
# objects are built member by member, so reading their addresses and port
# names never looks at the IP or the port, only at the keys.

def L.endpoint.legacy_not_found():
  {==}

def L.endpoint.legacy_without_slice():
  {==}

def L.endpoint.legacy_with_slice():
  {==}

def L.endpoint.create_or_patch_v1():
  {==}

def L.endpoint.create_or_patch_v1beta1():
  {==}

def L.endpoint.register_reverse():
  {==}

def L.endpoint.reconcile_not_synced():
  {==}

def L.endpoint.reconcile_not_found():
  {==}

def L.endpoint.reconcile_new_virtual_service():
  {==}

def L.endpoint.reconcile_load_balancer_endpoints():
  {==}

def L.endpoint.standalone_create_ipv4():
  {==}

def L.endpoint.standalone_create_ipv6():
  {==}

def L.endpoint.standalone_steady():
  {==}

def L.endpoint.standalone_moved():
  {==}

def L.endpoint.standalone_endpoints_object():
  {==}

def L.endpoint.standalone_slice_object():
  {==}

def L.endpoint.standalone_endpoints_one_address(ip, port):
  {==}

def L.endpoint.standalone_endpoints_one_https_port(ip, port):
  {==}

def L.endpoint.standalone_slice_one_address(ip, port):
  {==}

def L.endpoint.standalone_slice_one_https_port(ip, port):
  {==}
