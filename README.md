# QEMU-Pinning: QEMU fork with pinning (affinity) support

Fork of QEMU, with support for pinning virtual cpus/cores/threads to the physical counterparts.

- [QEMU-Pinning: QEMU fork with pinning (affinity) support](#qemu-pinning-qemu-fork-with-pinning-affinity-support)
  - [Patch notes](#patch-notes)
  - [Building the project (including QEMU binary)](#building-the-project-including-qemu-binary)
  - [Commandline options](#commandline-options)
  - [Pinning common scenarios/scripts, and Windows mapping](#pinning-common-scenariosscripts-and-windows-mapping)
    - [One vCPU per core](#one-vcpu-per-core)
    - [One vCPUs per core/thread, except one core](#one-vcpus-per-corethread-except-one-core)
    - [Arbitrary number of vCPUs](#arbitrary-number-of-vcpus)
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

The project will be built, and display the locations of the binaries (system/user emulators).

A few important notes:

- this is a rather minimal build configuration, and it won't have any secondary feature aside the mentioned ones (GTK VGA, Pulseaudio, and USB); if you need more features, you can easily alter the `./configure` command in the build script;
- the project itself is composed of many components, so copying the binary itself to another location will not work.

It's trivial to adjust the script to run it on other distributions.

## Commandline options

Pinning is exposed through the `-vcpu` commandline option; this is the generic structure of a pinned execution:

```sh
qemu-system-x86_64 \
  -smp $total_vcpus,cores=$vcores,sockets=$vsockets,threads=$vthreads \
  -vcpu vcpunum=$vcpu_number,affinity=$host_processor_number \
  -vcpu vcpunum=$vcpu_number,affinity=$host_processor_number \
  ...
```

The following section will show common pinning scenarios, and convenient scripts that prepare them.

## Pinning common scenarios/scripts, and Windows mapping

The scenarios in this section (except where specified) apply to a processor with the following topology (a Ryzen 7 3800x):

```
$ lstopo --of console --no-io --no-caches

Machine (31GB total) + Package L#0
  NUMANode L#0 (P#0 31GB)
  Core L#0
    PU L#0 (P#0)
    PU L#1 (P#8)
  Core L#1
    PU L#2 (P#1)
    PU L#3 (P#9)
  Core L#2
    PU L#4 (P#2)
    PU L#5 (P#10)
  Core L#3
    PU L#6 (P#3)
    PU L#7 (P#11)
  Core L#4
    PU L#8 (P#4)
    PU L#9 (P#12)
  Core L#5
    PU L#10 (P#5)
    PU L#11 (P#13)
  Core L#6
    PU L#12 (P#6)
    PU L#13 (P#14)
  Core L#7
    PU L#14 (P#7)
    PU L#15 (P#15)
```

Empyrically, based on the scripts presented here, QEMU exposes the threads (vcpus) sequentially, and Windows interprets physical processors as contiguous blocks.

Therefore, if one wants to, say, pin core 0 and its two threads, they need to pass:

```
-smp 2,cores=1,sockets=1,threads=2 -vcpu vcpunum=0,affinity=0 -vcpu vcpunum=1,affinity=8
```

### One vCPU per core

Assign one virtual CPU per host core (*not per thread*):

```sh
CORES_NUMBER=$(lscpu --all -p=CORE | grep -v '^#' | sort | uniq | wc -l)

SMP_PARAMS="  -smp $CORES_NUMBER,cores=$CORES_NUMBER,sockets=1,threads=1"

for core_number in $(seq 1 $CORES_NUMBER); do
  SMP_PARAMS+="  \\
  -vcpu vcpunum=$((core_number - 1)),affinity=$((core_number - 1))"
done

echo "$SMP_PARAMS"
#  -smp 8,cores=8,sockets=1,threads=1  \
#  -vcpu vcpunum=0,affinity=0  \
#  -vcpu vcpunum=1,affinity=1  \
#  -vcpu vcpunum=2,affinity=2  \
#  -vcpu vcpunum=3,affinity=3  \
#  -vcpu vcpunum=4,affinity=4  \
#  -vcpu vcpunum=5,affinity=5  \
#  -vcpu vcpunum=6,affinity=6  \
#  -vcpu vcpunum=7,affinity=7
```

### One vCPUs per core/thread, except one core

A typical configuration is to give all hardware cores/threads to the guest, with the exception of one core.

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

This will yield, in a Windows guest, 3 physical processors with 2 logical processors each, mapped to the host `CPU`s (1,5), (2,6) and (3,7).

The configuration above can be be automated with:

```sh
# Exclude the core 0, and cluster the threads, sorted by (socket,core)
CPUS_DATA=$(lscpu --all --parse=SOCKET,CORE,CPU | grep -vP '^(#|0,0)' | sort -t ',' -n)

THREADS=$(echo "$CPUS_DATA" | wc -l)
CORES=$(echo "$CPUS_DATA" | cut -d ',' -f 2 | sort | uniq | wc -l)
SOCKETS=$(echo "$CPUS_DATA" | cut -d ',' -f 1 | sort | uniq | wc -l)

SMP_PARAMS="  -smp $THREADS,cores=$CORES,threads=$(($THREADS / $CORES))"

vcpu=0; while read cpu_entry; do
  affinity=$(echo $cpu_entry | cut -d ',' -f 3)
  SMP_PARAMS+="  \\
  -vcpu vcpunum=$vcpu,affinity=$affinity"
  vcpu=$(($vcpu + 1))
done <<< "$CPUS_DATA"

echo "$SMP_PARAMS"
#  -smp 14,cores=7,threads=2  \
#  -vcpu vcpunum=0,affinity=1  \
#  -vcpu vcpunum=1,affinity=9  \
#  -vcpu vcpunum=2,affinity=10  \
#  -vcpu vcpunum=3,affinity=2  \
#  -vcpu vcpunum=4,affinity=11  \
#  -vcpu vcpunum=5,affinity=3  \
#  -vcpu vcpunum=6,affinity=12  \
#  -vcpu vcpunum=7,affinity=4  \
#  -vcpu vcpunum=8,affinity=13  \
#  -vcpu vcpunum=9,affinity=5  \
#  -vcpu vcpunum=10,affinity=14  \
#  -vcpu vcpunum=11,affinity=6  \
#  -vcpu vcpunum=12,affinity=15  \
#  -vcpu vcpunum=13,affinity=7
```

### Arbitrary number of vCPUs

The following script, courtesy of Frédéric Pétrot (University of Grenoble), prepare a pinning for an arbitrary number of vCPUs, passed to the script:

```sh
#!/bin/bash

if test -z "$1"; then
  echo "$0: Please provide the number of virtual cpus"
  exit
fi

nvcpus=$1

# Chosing to sort in such a way that it is easier to see if there is a bug in the program :)
CPUS_DATA=$(lscpu --all --parse=SOCKET,CORE,CPU | grep -vP '^(#)' | sort -t ',' -k 1,1n -k 2,2n -k 3,3n)

declare CPUS_ENTRY
i=0; while read cpu_entry; do
  CPUS_ENTRY[$i]=$cpu_entry
  i=$(($i + 1))
done <<< "$CPUS_DATA"
cpus=$(nproc)

THREADS=$(echo "$CPUS_DATA" | wc -l)
CORES=$(echo "$CPUS_DATA" | cut -d ',' -f 2 | sort | uniq | wc -l)
SOCKETS=$(echo "$CPUS_DATA" | cut -d ',' -f 1 | sort | uniq | wc -l)

# A bit of a wild guess, ...
threads=$(($THREADS/$CORES))
cores=$(($(($nvcpus + 1))/$threads))

QEMU_SMP="  -smp $nvcpus,cores=$cores,threads=$threads"

for vcpu in $(seq 0 $(($nvcpus - 1))); do
  affinity=$(echo ${CPUS_ENTRY[$(($vcpu%$cpus))]} | cut -d ',' -f 3)
  QEMU_AFFINITIES="$QEMU_AFFINITIES  \\
  -vcpu vcpunum=$vcpu,affinity=$affinity"
done

echo "$QEMU_SMP $QEMU_AFFINITIES"
```

Result of `vcpu-assign.sh 10`:

```sh
  -smp 10,cores=5,threads=2   \
  -vcpu vcpunum=0,affinity=0  \
  -vcpu vcpunum=1,affinity=8  \
  -vcpu vcpunum=2,affinity=1  \
  -vcpu vcpunum=3,affinity=9  \
  -vcpu vcpunum=4,affinity=2  \
  -vcpu vcpunum=5,affinity=10  \
  -vcpu vcpunum=6,affinity=3  \
  -vcpu vcpunum=7,affinity=11  \
  -vcpu vcpunum=8,affinity=4  \
  -vcpu vcpunum=9,affinity=12
```

## Verifying the pinning

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

## Multi-socket CPUs

This patch should also support sockets, but it can't be tested on my machine(s).

## Repository (git) structure

The master branch is always the latest QEMU release version (generally, with a lag of a few days, unless there are specific issues), with the latest version of the pinning patch and build script.

The top 3 master commits are (in order from head):

0. pinning patch
1. building script; `README.md`; gitignore update
2. allow symlinks in Samba shares patch

The repository contains two lines of branches:

- `vX.Y.Z-pinning`: snaphots of previous QEMU versions, with the above commits applied
- `vX.Y.Z-pinning-changes`: version equivalent to `vX.Y.Z-pinning`, with minor changes separated (since the `master` structure is rigid, without this line, the history would be lost)

Only the `master` and the latest `-changes` branch are actively developed (both correspond to the latest QEMU version). There are no guarantees about updates to old version branches.

## Why not libvirt?

I've found libvirt to be a very interesting idea, but ultimately, a leaky abstraction:

1. the compatibility with all the QEMU versions is not guaranteed (for example, v2.10 wasn't supported for some time after release);
2. the typical GUI (`virt-manager`) is poor (many entries must be edited via `virsh edit`);
3. since the ultimate reference is QEMU, one ends up thinking how to make things work with QEMU, then finding the libvirt configuration counterpart.

Point 3 may be caused by my poor libvirt knowledge, but the fact that libvirt's functionality is built on top of QEMU always stands, and complex QEMU configurations are bound to have translation challenges.

I'm sure of course, that for simple setups, `libvirt` + `virt-manager` may work very well.
