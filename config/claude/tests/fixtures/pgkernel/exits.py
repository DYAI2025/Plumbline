"""Announces pid/pgid, then exits with the code in argv[1]."""
import os, sys
sys.stdout.write("PG pid=%d pgid=%d\n" % (os.getpid(), os.getpgid(0)))
sys.stdout.flush()
sys.exit(int(sys.argv[1]))
