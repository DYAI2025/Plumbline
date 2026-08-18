"""Validates a binding that names its own PARENT's process group."""
import os, sys
sys.path.insert(0, sys.argv[3])
import lib_process_group as K
parent_pid, parent_pgid = int(sys.argv[1]), int(sys.argv[2])
live_parent_pgid = os.getpgid(os.getppid())
sys.stdout.write("CHILD ppid=%d live_parent_pgid=%d claimed=%d\n"
                 % (os.getppid(), live_parent_pgid, parent_pgid))
v = K.validate_bound_group(K.Binding(target_pid=parent_pid, initial_pgid=parent_pgid))
sys.stdout.write("VERDICT state=%s reason=%s\n" % (v.state, v.reason))
