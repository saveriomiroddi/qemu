# QEMU-Pinning: QEMU fork with pinning (affinity) support

Fork of QEMU, with support for pinning virtual cpus/cores/threads to the physical counterparts.

## Table of contents

- [Patch notes](#patch-notes)
- [Building the project (including QEMU binary)](#building-the-project-including-qemu-binary)
  - [Generic execution](#generic-execution)
  - [More advanced execution](#more-advanced-execution)
  - [Verifying the pinning](#verifying-the-pinning)
  - [Multi-socket CPUs](#multi-socket-cpus)
- [Repository (git) structure](#repository-git-structure)
- [Why not libvirt?](#why-not-libvirt)

## Patch notes

The code was originally a QEMU 2.4.1 patch [published on the QEMU mailing list](https://www.mail-archive.com/qemu-discuss%40nongnu.org/msg02253.html); I've made significant fixes/cleanups, and I periodically rebase/update it on top of the release QEMU versions.

Pinning is accomplished using the Linux interfaces `cpu_set_t` (and related macros) and `pthread_setaffinity_np`.

## Building the project (including QEMU binary)

A script is provided for building the project on common Linux distros. The master branch is always the most recent QEMU release version (or at least, a very recent one), so it's appropriate for general use.

From the project root, run:

```sh
./build_pinning_qemu_binary.sh
```

The project will be built, and display the binary location.

A few important notes:

- this is a rather minimal build configuration, and it won't have any secondary feature aside the mentioned ones (GTK VGA, Pulseaudio, and USB); if you need more features, you can easily alter the `./configure` command in the build script;
- the project itself is composed of many components, so copying the binary itself to another location will not work.

It's trivial to adjust the script to run it on other distributions.

### Generic execution

Pinning (-related) QEMU options:

```
-smp <total_vcpus>,cores=<vcores>,sockets=<vsockets>,threads=<vthreads>
-vcpu vcpunum=<vcpu_number>,affinity=<host_cpu_number>
```

Convenient bash script to assign one virtual CPU per core (*not per thread*):

```sh
CORES_NUMBER=$(lscpu --all -p=CORE | grep -v ^# | sort | uniq | wc -l)

SMP_PARAMS="-smp $CORES_NUMBER,cores=$CORES_NUMBER,sockets=1,threads=1"

for core_number in $(seq 1 $CORES_NUMBER); do
  PINNING_PARAMS=" $PINNING_PARAMS -vcpu vcpunum=$((core_number - 1)),affinity=$((core_number - 1))"
done

$QEMU_BINARY_PATH $SMP_PARAMS $PINNING_PARAMS $OTHER_PARAMS
```

### More advanced execution

It's possible to have more complex configurations. For example, a typical configuration is to give all cores (and threads) to the guest, with the exception of one core.

First, one needs to obtain the host cpu layout; a simple way is:

```sh
$ lscpu --extended

CPU NODE SOCKET CORE L1d:L1i:L2:L3 ONLINE MAXMHZ    MINMHZ
0   0    0      0    0:0:0:0       yes    4200,0000 800,0000
1   0    0      1    1:1:1:0       yes    4200,0000 800,0000
2   0    0      2    2:2:2:0       yes    4200,0000 800,0000
3   0    0      3    3:3:3:0       yes    4200,0000 800,0000
4   0    0      0    0:0:0:0       yes    4200,0000 800,0000
5   0    0      1    1:1:1:0       yes    4200,0000 800,0000
6   0    0      2    2:2:2:0       yes    4200,0000 800,0000
7   0    0      3    3:3:3:0       yes    4200,0000 800,0000
```

`CPU` represents a CPU from a Linux perspective, therefore, if the CPU supports SMT ("Hyper-threading" on Intel), each `CPU` is a thread.  
In this case, for example, `CORE 0` will have two threads, represented by `CPU 0` and `CPU 4`.

With the configuration above, and the objective of passing all except one core, the pinning parameters are:

```
-smp 6,cores=3,sockets=1,threads=2
-vcpu vcpunum=0,affinity=1 -vcpu vcpunum=1,affinity=5
-vcpu vcpunum=2,affinity=2 -vcpu vcpunum=3,affinity=6
-vcpu vcpunum=4,affinity=3 -vcpu vcpunum=5,affinity=7
```

Such configuration will yield, in a Windows guest, 3 physical processors with 2 logical processors each, mapped to the host `CPU`s (1,5), (2,6) and (3,7).

Note that according to this this result, QEMU exposes the threads (vcpus) sequentially, and Windows interprets physical processors as contiguous blocks.

The configuration above can be be automated with an interesting exercise in scripting:

```sh
# Exclude the core 0, and cluster the threads, sorted by (socket,core)
CPUS_DATA=$(lscpu --all --parse=SOCKET,CORE,CPU | grep -vP '^(#|0,0)' | sort -t ',' -n)

THREADS=$(echo "$CPUS_DATA" | wc -l)
CORES=$(echo "$CPUS_DATA" | cut -d ',' -f 2 | sort | uniq | wc -l)
SOCKETS=$(echo "$CPUS_DATA" | cut -d ',' -f 1 | sort | uniq | wc -l)

QEMU_SMP="-smp $THREADS,cores=$CORES,threads=$(($THREADS / $CORES))"

vcpu=0; while read cpu_entry; do
  affinity=$(echo $cpu_entry | cut -d ',' -f 3)
  QEMU_AFFINITIES="$QEMU_AFFINITIES -vcpu vcpunum=$vcpu,affinity=$affinity"
  vcpu=$(($vcpu + 1))
done <<< "$CPUS_DATA"

echo "$QEMU_SMP $QEMU_AFFINITIES"
```

### Verifying the pinning

Pinning can be verified in many ways.

An easy one is to use `htop` on the host, and the Microsoft-advised [Cpu Stress tool](https://blogs.msdn.microsoft.com/vijaysk/2012/10/26/tools-to-simulate-cpu-memory-disk-load) on the guest, then rotate the affinity via Task Manager.

The procedure is:

- run `htop` on the host
- start the guest
- run the CPI Stress tool, using 1 thread active, with `Maximum` activity
- open the Task manager, `Details` tab
- right click on `CPUSTRES.EXE`
- now set one CPU at a time, and check which CPU will have 100% occupation on the host

Don't forget that `htop` CPU indexes equal to Linux + 1!

### Multi-socket CPUs

This patch should also support sockets, but it can't be tested on my machine(s).

## Repository (git) structure

The master branch is always the latest QEMU release version (generally, with a lag of a few days, unless there are specific issues).

The HEAD commit is the pinning patch, and HEAD~ contains the `README.md` and `build_pinning_qemu_binary.sh` (plus, updates to `.gitignore`).

I provide branches for past versions, and for the current version (which matches `master`); they're named `vx.x.x-pinning`, and have the same structure; therefore, in order to build an older version, just checkout the branch and run the build script.

## Why not libvirt?

I've found libvirt to be a very interesting idea, but ultimately, a leaky abstraction:

1. the compatibility with all the QEMU versions is not guaranteed (for example, v2.10 wasn't supported for some time after release);
2. the typical GUI (`virt-manager`) is poor (many entries must be edited via `virsh edit`);
3. since the ultimate reference is QEMU, one ends up thinking how to make things work with QEMU, then finding the libvirt configuration counterpart.

Point 3 may be caused by my poor libvirt knowledge, but the fact that libvirt's functionality is built on top of QEMU always stands, and complex QEMU configurations are bound to have translation challenges.

I'm sure of course, that for simple setups, `libvirt` + `virt-manager` may work very well.
