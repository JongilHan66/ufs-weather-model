#!/bin/bash
set -eux

SECONDS=0

hostname

die() { echo "$@" >&2; exit 1; }
usage() {
  set +x
  echo
  echo "Usage: $0 -c | -e | -h | -k | -l <file> | -m | -n <name> | -r "
  echo
  echo "  -c  create new baseline results"
  echo "  -e  use ecFlow workflow manager"
  echo "  -h  display this help"
  echo "  -k  keep run directory"
  echo "  -l  runs test specified in <file>"
  echo "  -m  compare against new baseline results"
  echo "  -n  run single test <name>"
  echo "  -r  use Rocoto workflow manager"
  echo
  set -x
  exit 1
}

[[ $# -eq 0 ]] && usage

rt_single() {
  local compile_line=''
  local run_line=''
  while read -r line || [ "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ ${#line} == 0 ]] && continue
    [[ $line == \#* ]] && continue

    if [[ $line == COMPILE* ]] ; then
      MACHINES=$(echo $line | cut -d'|' -f3 | sed -e 's/^ *//' -e 's/ *$//')
      if [[ ${MACHINES} == '' ]]; then
        compile_line=$line
      elif [[ ${MACHINES} == -* ]]; then
        [[ ${MACHINES} =~ ${MACHINE_ID} ]] || compile_line=$line
      elif [[ ${MACHINES} == +* ]]; then
        [[ ${MACHINES} =~ ${MACHINE_ID} ]] && compile_line=$line
      fi
    fi

    if [[ $line =~ RUN ]]; then
      tmp_test=$(echo $line | cut -d'|' -f2 | sed -e 's/^ *//' -e 's/ *$//')
      if [[ $SINGLE_NAME == $tmp_test && $compile_line != '' ]]; then
        echo $compile_line >$TESTS_FILE
        echo $line >>$TESTS_FILE
        break
      fi
    fi
  done <'rt.conf'

  if [[ ! -f $TESTS_FILE ]]; then
    echo "$SINGLE_NAME does not exist or cannot be run on $MACHINE_ID"
    exit 1
  fi
}

rt_35d() {
  local sy=$(echo ${DATE_35D} | cut -c 1-4)
  local sm=$(echo ${DATE_35D} | cut -c 5-6)
  local new_test_name="tests/${TEST_NAME}_${DATE_35D}"
  rm -f $new_test_name
  cp tests/$TEST_NAME $new_test_name

  sed -i -e "s/\(export SYEAR\)/\1=\"$sy\"/" $new_test_name
  sed -i -e "s/\(export SMONTH\)/\1=\"$sm\"/" $new_test_name

  TEST_NAME=${new_test_name#tests/}
}

rt_trap() {
  [[ ${ROCOTO:-false} == true ]] && rocoto_kill
  [[ ${ECFLOW:-false} == true ]] && ecflow_kill
  cleanup
}

cleanup() {
  rm -rf ${LOCKDIR}
  [[ ${ECFLOW:-false} == true ]] && ecflow_stop
  trap 0
  exit
}

trap '{ echo "rt.sh interrupted"; rt_trap ; }' INT
trap '{ echo "rt.sh quit"; rt_trap ; }' QUIT
trap '{ echo "rt.sh terminated"; rt_trap ; }' TERM
trap '{ echo "rt.sh error on line $LINENO"; cleanup ; }' ERR
trap '{ echo "rt.sh finished"; cleanup ; }' EXIT

# PATHRT - Path to regression tests directory
readonly PATHRT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
cd ${PATHRT}

# PATHTR - Path to nmmb trunk directory
readonly PATHTR=$( cd ${PATHRT}/.. && pwd )

# make sure only one instance of rt.sh is running
readonly LOCKDIR="${PATHRT}"/lock
if mkdir "${LOCKDIR}" ; then
  echo $(hostname) $$ > "${LOCKDIR}/PID"
else
  echo "Only one instance of rt.sh can be running at a time"
  exit 1
fi

# Default compiler "intel"
export RT_COMPILER=${RT_COMPILER:-intel}

source detect_machine.sh
source rt_utils.sh

source $PATHTR/NEMS/src/conf/module-setup.sh.inc

if [[ $MACHINE_ID = wcoss_cray ]]; then

  module load xt-lsfhpc

  module use /usrx/local/emc_rocoto/modulefiles
  module load rocoto/1.3.0rc2
  ROCOTORUN=$(which rocotorun)
  ROCOTOSTAT=$(which rocotostat)
  ROCOTOCOMPLETE=$(which rocotocomplete)
  ROCOTO_SCHEDULER=lsfcray

  module use /gpfs/hps/nco/ops/nwtest/modulefiles
  module load ecflow/intel/4.17.0.1
  ECFLOW_START=${ECF_ROOT}/bin/ecflow_start.sh
  ECF_PORT=$(grep $USER /usrx/local/sys/ecflow/assigned_ports.txt | awk '{print $2}')
  module load python/3.6.3

  DISKNM=/gpfs/hps3/emc/nems/noscrub/emc.nemspara/RT
  QUEUE=debug
  COMPILE_QUEUE=dev
  PARTITION=
  ACCNR=GFS-DEV
  if [[ -d /gpfs/hps3/ptmp ]] ; then
      STMP=/gpfs/hps3/stmp
      PTMP=/gpfs/hps3/stmp
  else
      STMP=/gpfs/hps3/stmp
      PTMP=/gpfs/hps3/ptmp
  fi
  SCHEDULER=lsf
  cp fv3_conf/fv3_bsub.IN_wcoss_cray fv3_conf/fv3_bsub.IN
  cp fv3_conf/compile_bsub.IN_wcoss_cray fv3_conf/compile_bsub.IN

elif [[ $MACHINE_ID = wcoss_dell_p3 ]]; then

  module load lsf/10.1
  module load python/3.6.3

  module use /usrx/local/dev/emc_rocoto/modulefiles
  module load ruby/2.5.1 rocoto/1.3.0rc2
  ROCOTORUN=$(which rocotorun)
  ROCOTOSTAT=$(which rocotostat)
  ROCOTOCOMPLETE=$(which rocotocomplete)
  ROCOTO_SCHEDULER=lsf

  module load ips/18.0.1.163
  module load ecflow/4.17.0
  ECFLOW_START=${ECF_ROOT}/bin/ecflow_start.sh
  ECF_PORT=$(grep $USER /usrx/local/sys/ecflow/assigned_ports.txt | awk '{print $2}')

  DISKNM=/gpfs/dell2/emc/modeling/noscrub/emc.nemspara/RT
  QUEUE=debug
  COMPILE_QUEUE=dev_transfer
  PARTITION=
  ACCNR=GFS-DEV
  STMP=/gpfs/dell2/stmp
  PTMP=/gpfs/dell2/ptmp
  SCHEDULER=lsf
  cp fv3_conf/fv3_bsub.IN_wcoss_dell_p3 fv3_conf/fv3_bsub.IN
  cp fv3_conf/compile_bsub.IN_wcoss_dell_p3 fv3_conf/compile_bsub.IN

elif [[ $MACHINE_ID = wcoss2 ]]; then

  source /apps/prod/lmodules/startLmod

  #module use /usrx/local/dev/emc_rocoto/modulefiles
  #module load ruby/2.5.1 rocoto/1.3.0rc2
  #ROCOTORUN=$(which rocotorun)
  #ROCOTOSTAT=$(which rocotostat)
  #ROCOTOCOMPLETE=$(which rocotocomplete)
  #ROCOTO_SCHEDULER=lsf

  #module load ips/18.0.1.163
  #module load ecflow/4.7.1
  #ECFLOW_START=${ECF_ROOT}/intel/bin/ecflow_start.sh
  #ECF_PORT=$(grep $USER /usrx/local/sys/ecflow/assigned_ports.txt | awk '{print $2}')

  DISKNM=/lfs/h1/emc/ptmp/Dusan.Jovic/RT
  QUEUE=workq
  COMPILE_QUEUE=workq
  PARTITION=
  ACCNR=GFS-DEV
  STMP=/lfs/h1/emc/stmp
  PTMP=/lfs/h1/emc/ptmp
  SCHEDULER=pbs
  cp fv3_conf/fv3_qsub.IN_wcoss2 fv3_conf/fv3_qsub.IN
  cp fv3_conf/compile_qsub.IN_wcoss2 fv3_conf/compile_qsub.IN

elif [[ $MACHINE_ID = gaea.* ]]; then

  export PATH=/lustre/f2/pdata/esrl/gsd/contrib/miniconda3/4.8.3/envs/ufs-weather-model/bin:/lustre/f2/pdata/esrl/gsd/contrib/miniconda3/4.8.3/bin:$PATH
  export PYTHONPATH=/lustre/f2/pdata/esrl/gsd/contrib/miniconda3/4.8.3/envs/ufs-weather-model/lib/python3.8/site-packages:/lustre/f2/pdata/esrl/gsd/contrib/miniconda3/4.8.3/lib/python3.8/site-packages
  ECFLOW_START=/lustre/f2/pdata/esrl/gsd/contrib/miniconda3/4.8.3/envs/ufs-weather-model/bin/ecflow_start.sh
  ECF_PORT=$(( $(id -u) + 1500 ))

  DISKNM=/lustre/f2/pdata/ncep_shared/emc.nemspara/RT
  QUEUE=normal
  COMPILE_QUEUE=normal
#  ACCNR=cmp
  PARTITION=c4
  STMP=/lustre/f2/scratch
  PTMP=/lustre/f2/scratch

  SCHEDULER=slurm
  cp fv3_conf/fv3_slurm.IN_gaea fv3_conf/fv3_slurm.IN
  cp fv3_conf/compile_slurm.IN_gaea fv3_conf/compile_slurm.IN

elif [[ $MACHINE_ID = hera.* ]]; then

  module load rocoto
  ROCOTORUN=$(which rocotorun)
  ROCOTOSTAT=$(which rocotostat)
  ROCOTOCOMPLETE=$(which rocotocomplete)
  ROCOTO_SCHEDULER=slurm

  export PATH=/scratch1/NCEPDEV/nems/emc.nemspara/soft/miniconda3/bin:$PATH
  export PYTHONPATH=/scratch1/NCEPDEV/nems/emc.nemspara/soft/miniconda3/lib/python3.8/site-packages
  ECFLOW_START=/scratch1/NCEPDEV/nems/emc.nemspara/soft/miniconda3/bin/ecflow_start.sh
  ECF_PORT=$(( $(id -u) + 1500 ))

  QUEUE=batch
  COMPILE_QUEUE=batch

  #ACCNR=fv3-cpu
  PARTITION=
  dprefix=/scratch1/NCEPDEV
  DISKNM=$dprefix/nems/emc.nemspara/RT
  STMP=$dprefix/stmp4
  PTMP=$dprefix/stmp2

  SCHEDULER=slurm
  cp fv3_conf/fv3_slurm.IN_hera fv3_conf/fv3_slurm.IN
  cp fv3_conf/compile_slurm.IN_hera fv3_conf/compile_slurm.IN

elif [[ $MACHINE_ID = orion.* ]]; then

  module load gcc/8.3.0

  module load contrib rocoto/1.3.1
  ROCOTORUN=$(which rocotorun)
  ROCOTOSTAT=$(which rocotostat)
  ROCOTOCOMPLETE=$(which rocotocomplete)
  export PATH=/work/noaa/nems/emc.nemspara/soft/miniconda3/bin:$PATH
  export PYTHONPATH=/work/noaa/nems/emc.nemspara/soft/miniconda3/lib/python3.8/site-packages
  ECFLOW_START=/work/noaa/nems/emc.nemspara/soft/miniconda3/bin/ecflow_start.sh
  ECF_PORT=$(( $(id -u) + 1500 ))

  QUEUE=batch
  COMPILE_QUEUE=batch
#  ACCNR= # detected in detect_machine.sh
  PARTITION=orion
  dprefix=/work/noaa/stmp/${USER}
  DISKNM=/work/noaa/nems/emc.nemspara/RT
  STMP=$dprefix/stmp
  PTMP=$dprefix/stmp

  SCHEDULER=slurm
  cp fv3_conf/fv3_slurm.IN_orion fv3_conf/fv3_slurm.IN
  cp fv3_conf/compile_slurm.IN_orion fv3_conf/compile_slurm.IN

elif [[ $MACHINE_ID = jet.* ]]; then

  module load rocoto/1.3.2
  ROCOTORUN=$(which rocotorun)
  ROCOTOSTAT=$(which rocotostat)
  ROCOTOCOMPLETE=$(which rocotocomplete)
  ROCOTO_SCHEDULER=slurm

  export PATH=/lfs4/HFIP/hfv3gfs/software/miniconda3/4.8.3/envs/ufs-weather-model/bin:/lfs4/HFIP/hfv3gfs/software/miniconda3/4.8.3/bin:$PATH
  export PYTHONPATH=/lfs4/HFIP/hfv3gfs/software/miniconda3/4.8.3/envs/ufs-weather-model/lib/python3.8/site-packages:/lfs4/HFIP/hfv3gfs/software/miniconda3/4.8.3/lib/python3.8/site-packages
  ECFLOW_START=/lfs4/HFIP/hfv3gfs/software/miniconda3/4.8.3/envs/ufs-weather-model/bin/ecflow_start.sh
  ECF_PORT=$(( $(id -u) + 1500 ))

  QUEUE=batch
  COMPILE_QUEUE=batch
  ACCNR=h-nems
  PARTITION=xjet
  DISKNM=/lfs4/HFIP/h-nems/emc.nemspara/RT
  dprefix=/lfs4/HFIP/h-nems/$USER
  STMP=$dprefix/RT_BASELINE
  PTMP=$dprefix/RT_RUNDIRS

  SCHEDULER=slurm
  cp fv3_conf/fv3_slurm.IN_jet fv3_conf/fv3_slurm.IN
  cp fv3_conf/compile_slurm.IN_jet fv3_conf/compile_slurm.IN

elif [[ $MACHINE_ID = cheyenne.* ]]; then

  export PATH=/glade/p/ral/jntp/tools/miniconda3/4.8.3/envs/ufs-weather-model/bin:/glade/p/ral/jntp/tools/miniconda3/4.8.3/bin:$PATH
  export PYTHONPATH=/glade/p/ral/jntp/tools/miniconda3/4.8.3/envs/ufs-weather-model/lib/python3.8/site-packages:/glade/p/ral/jntp/tools/miniconda3/4.8.3/lib/python3.8/site-packages
  ECFLOW_START=/glade/p/ral/jntp/tools/miniconda3/4.8.3/envs/ufs-weather-model/bin/ecflow_start.sh
  ECF_PORT=$(( $(id -u) + 1500 ))

  QUEUE=economy
  COMPILE_QUEUE=economy
  PARTITION=
  dprefix=/glade/scratch
  DISKNM=/glade/p/ral/jntp/GMTB/ufs-weather-model/RT
  STMP=$dprefix
  PTMP=$dprefix
  SCHEDULER=pbs
  cp fv3_conf/fv3_qsub.IN_cheyenne fv3_conf/fv3_qsub.IN
  cp fv3_conf/compile_qsub.IN_cheyenne fv3_conf/compile_qsub.IN

elif [[ $MACHINE_ID = stampede.* ]]; then

  export PYTHONPATH=
  ECFLOW_START=
  QUEUE=skx-normal
  COMPILE_QUEUE=skx-dev
  PARTITION=
  ACCNR=TG-EES200015
  dprefix=$SCRATCH/ufs-weather-model/run
  DISKNM=/work/07736/minsukji/stampede2/ufs-weather-model/RT
  STMP=$dprefix
  PTMP=$dprefix
  SCHEDULER=slurm
  MPIEXEC=ibrun
  MPIEXECOPTS=
  cp fv3_conf/fv3_slurm.IN_stampede fv3_conf/fv3_slurm.IN

else
  die "Unknown machine ID, please edit detect_machine.sh file"
fi

mkdir -p ${STMP}/${USER}

# Different own baseline directories for different compilers on Theia/Cheyenne
NEW_BASELINE=${STMP}/${USER}/FV3_RT/REGRESSION_TEST
if [[ $MACHINE_ID = hera.* ]] || [[ $MACHINE_ID = orion.* ]] || [[ $MACHINE_ID = cheyenne.* ]] || [[ $MACHINE_ID = gaea.* ]] || [[ $MACHINE_ID = jet.* ]]; then
    NEW_BASELINE=${NEW_BASELINE}_${RT_COMPILER^^}
fi

# Overwrite default RUNDIR_ROOT if environment variable RUNDIR_ROOT is set
RUNDIR_ROOT=${RUNDIR_ROOT:-${PTMP}/${USER}/FV3_RT}/rt_$$
mkdir -p ${RUNDIR_ROOT}

CREATE_BASELINE=false
ROCOTO=false
ECFLOW=false
KEEP_RUNDIR=false
SINGLE_NAME=''
TEST_35D=false

TESTS_FILE='rt.conf'

while getopts ":cl:mn:kreh" opt; do
  case $opt in
    c)
      CREATE_BASELINE=true
      ;;
    l)
      TESTS_FILE=$OPTARG
      ;;
    m)
      # redefine RTPWD to point to newly created baseline outputs
      RTPWD=${NEW_BASELINE}
      ;;
    n)
      SINGLE_NAME=$OPTARG
      TESTS_FILE='rt.conf.single'
      rm -f $TESTS_FILE
      ;;
    k)
      KEEP_RUNDIR=true
      ;;
    r)
      ROCOTO=true
      ECFLOW=false
      ;;
    e)
      ECFLOW=true
      ROCOTO=false
      ;;
    h)
      usage
      ;;
    \?)
      usage
      die "Invalid option: -$OPTARG"
      ;;
    :)
      usage
      die "Option -$OPTARG requires an argument."
      ;;
  esac
done

if [[ $SINGLE_NAME != '' ]]; then
  rt_single
fi

if [[ $TESTS_FILE =~ '35d' ]]; then
  TEST_35D=true
fi

BL_DATE=20210517
if [[ $MACHINE_ID = hera.* ]] || [[ $MACHINE_ID = orion.* ]] || [[ $MACHINE_ID = cheyenne.* ]] || [[ $MACHINE_ID = gaea.* ]] || [[ $MACHINE_ID = jet.* ]]; then
  RTPWD=${RTPWD:-$DISKNM/NEMSfv3gfs/develop-${BL_DATE}/${RT_COMPILER^^}}
else
  RTPWD=${RTPWD:-$DISKNM/NEMSfv3gfs/develop-${BL_DATE}}
fi

INPUTDATA_ROOT=${INPUTDATA_ROOT:-$DISKNM/NEMSfv3gfs/input-data-20210518}
INPUTDATA_ROOT_WW3=${INPUTDATA_ROOT}/WW3_input_data_20210503
INPUTDATA_ROOT_BMIC=${INPUTDATA_ROOT_BMIC:-$DISKNM/NEMSfv3gfs/BM_IC-20210212}

shift $((OPTIND-1))
[[ $# -gt 1 ]] && usage

if [[ $CREATE_BASELINE == true ]]; then
  #
  # prepare new regression test directory
  #
  rm -rf "${NEW_BASELINE}"
  mkdir -p "${NEW_BASELINE}"
fi

REGRESSIONTEST_LOG=${PATHRT}/RegressionTests_$MACHINE_ID.log

date > ${REGRESSIONTEST_LOG}
echo "Start Regression test" >> ${REGRESSIONTEST_LOG}
echo                         >> ${REGRESSIONTEST_LOG}

source default_vars.sh

JOB_NR=0
TEST_NR=0
COMPILE_NR=0
COMPILE_PREV_WW3_NR=''
rm -f fail_test

export LOG_DIR=${PATHRT}/log_$MACHINE_ID
rm -rf ${LOG_DIR}
mkdir ${LOG_DIR}

if [[ $ROCOTO == true ]]; then

  ROCOTO_XML=${PATHRT}/rocoto_workflow.xml
  ROCOTO_DB=${PATHRT}/rocoto_workflow.db

  rm -f $ROCOTO_XML $ROCOTO_DB *_lock.db

  if [[ $MACHINE_ID = wcoss ]]; then
    QUEUE=dev
    COMPILE_QUEUE=dev
    ROCOTO_SCHEDULER=lsf
  elif [[ $MACHINE_ID = wcoss_cray ]]; then
    QUEUE=dev
    COMPILE_QUEUE=dev
    ROCOTO_SCHEDULER=lsfcray
  elif [[ $MACHINE_ID = wcoss_dell_p3 ]]; then
    QUEUE=dev
    COMPILE_QUEUE=dev_transfer
    ROCOTO_SCHEDULER=lsf
  elif [[ $MACHINE_ID = wcoss2 ]]; then
    QUEUE=workq
    COMPILE_QUEUE=workq
    ROCOTO_SCHEDULER=pbs
  elif [[ $MACHINE_ID = hera.* ]]; then
    QUEUE=batch
    COMPILE_QUEUE=batch
    ROCOTO_SCHEDULER=slurm
  elif [[ $MACHINE_ID = orion.* ]]; then
    QUEUE=batch
    COMPILE_QUEUE=batch
    ROCOTO_SCHEDULER=slurm
  elif [[ $MACHINE_ID = jet.* ]]; then
    QUEUE=batch
    COMPILE_QUEUE=batch
    ROCOTO_SCHEDULER=slurm
  else
    die "Rocoto is not supported on this machine $MACHINE_ID"
  fi

  cat << EOF > $ROCOTO_XML
<?xml version="1.0"?>
<!DOCTYPE workflow
[
  <!ENTITY PATHRT         "${PATHRT}">
  <!ENTITY LOG            "${LOG_DIR}">
  <!ENTITY PATHTR         "${PATHTR}">
  <!ENTITY RTPWD          "${RTPWD}">
  <!ENTITY INPUTDATA_ROOT "${INPUTDATA_ROOT}">
  <!ENTITY INPUTDATA_ROOT_WW3 "${INPUTDATA_ROOT_WW3}">
  <!ENTITY INPUTDATA_ROOT_BMIC "${INPUTDATA_ROOT_BMIC}">
  <!ENTITY RUNDIR_ROOT    "${RUNDIR_ROOT}">
  <!ENTITY NEW_BASELINE   "${NEW_BASELINE}">
]>
<workflow realtime="F" scheduler="${ROCOTO_SCHEDULER}" taskthrottle="20">
  <cycledef>197001010000 197001010000 01:00:00</cycledef>
  <log>&LOG;/workflow.log</log>
EOF

fi

if [[ $ECFLOW == true ]]; then

  # Default maximum number of compile and run jobs
  MAX_BUILDS=10
  MAX_JOBS=30

  # Reduce maximum number of compile jobs on jet.intel because of licensing issues
  if [[ $MACHINE_ID = jet.intel ]]; then
    MAX_BUILDS=5
  fi

  ECFLOW_RUN=${PATHRT}/ecflow_run
  ECFLOW_SUITE=regtest_$$
  rm -rf ${ECFLOW_RUN}
  mkdir -p ${ECFLOW_RUN}/${ECFLOW_SUITE}
  cp head.h tail.h ${ECFLOW_RUN}
  cat << EOF > ${ECFLOW_RUN}/${ECFLOW_SUITE}.def
suite ${ECFLOW_SUITE}
    edit ECF_HOME '${ECFLOW_RUN}'
    edit ECF_INCLUDE '${ECFLOW_RUN}'
    edit ECF_KILL_CMD kill -15 %ECF_RID% > %ECF_JOB%.kill 2>&1
    edit ECF_TRIES 1
    label src_dir '${PATHTR}'
    label run_dir '${RUNDIR_ROOT}'
    limit max_builds ${MAX_BUILDS}
    limit max_jobs ${MAX_JOBS}
EOF

  if [[ $MACHINE_ID = wcoss ]]; then
    QUEUE=dev
  elif [[ $MACHINE_ID = wcoss_cray ]]; then
    QUEUE=dev
  elif [[ $MACHINE_ID = wcoss_dell_p3 ]]; then
    QUEUE=dev
  elif [[ $MACHINE_ID = wcoss2 ]]; then
    QUEUE=workq
  elif [[ $MACHINE_ID = hera.* ]]; then
    QUEUE=batch
  elif [[ $MACHINE_ID = orion.* ]]; then
    QUEUE=batch
  elif [[ $MACHINE_ID = jet.* ]]; then
    QUEUE=batch
  elif [[ $MACHINE_ID = gaea.* ]]; then
    QUEUE=normal
  elif [[ $MACHINE_ID = cheyenne.* ]]; then
    QUEUE=economy
  else
    die "ecFlow is not supported on this machine $MACHINE_ID"
  fi

fi

##
## read rt.conf and then either execute the test script directly or create
## workflow description file
##

new_compile=false
in_metatask=false

[[ -f $TESTS_FILE ]] || die "$TESTS_FILE does not exist"

while read -r line || [ "$line" ]; do

  line="${line#"${line%%[![:space:]]*}"}"
  [[ ${#line} == 0 ]] && continue
  [[ $line == \#* ]] && continue

  JOB_NR=$( printf '%03d' $(( 10#$JOB_NR + 1 )) )

  if [[ $line == COMPILE* ]] ; then

    MAKE_OPT=$(echo $line | cut -d'|' -f2 | sed -e 's/^ *//' -e 's/ *$//')
    MACHINES=$(echo $line | cut -d'|' -f3 | sed -e 's/^ *//' -e 's/ *$//')
    CB=$(      echo $line | cut -d'|' -f4)

    [[ $CREATE_BASELINE == true && $CB != *fv3* ]] && continue

    if [[ ${MACHINES} != '' ]]; then
      if [[ ${MACHINES} == -* ]]; then
        [[ ${MACHINES} =~ ${MACHINE_ID} ]] && continue
      elif [[ ${MACHINES} == +* ]]; then
        [[ ${MACHINES} =~ ${MACHINE_ID} ]] || continue
      else
        echo "MACHINES=|${MACHINES}|"
        die "MACHINES spec must be either an empty string or start with either '+' or '-'"
      fi
    fi

    export COMPILE_NR=$( printf '%03d' $(( 10#$COMPILE_NR + 1 )) )

    cat << EOF > ${RUNDIR_ROOT}/compile_${COMPILE_NR}.env
    export JOB_NR=${JOB_NR}
    export COMPILE_NR=${COMPILE_NR}
    export MACHINE_ID=${MACHINE_ID}
    export RT_COMPILER=${RT_COMPILER}
    export PATHRT=${PATHRT}
    export PATHTR=${PATHTR}
    export SCHEDULER=${SCHEDULER}
    export ACCNR=${ACCNR}
    export QUEUE=${COMPILE_QUEUE}
    export PARTITION=${PARTITION}
    export ROCOTO=${ROCOTO}
    export ECFLOW=${ECFLOW}
    export REGRESSIONTEST_LOG=${REGRESSIONTEST_LOG}
    export LOG_DIR=${LOG_DIR}
EOF

    if [[ $ROCOTO == true ]]; then
      rocoto_create_compile_task
    elif [[ $ECFLOW == true ]]; then
      ecflow_create_compile_task
    else
      ./compile.sh $MACHINE_ID "${MAKE_OPT}" $COMPILE_NR > ${LOG_DIR}/compile_${COMPILE_NR}.log 2>&1
      mv compile_${COMPILE_NR}_time.log ${LOG_DIR}
    fi

    # Set RT_SUFFIX (regression test run directories and log files) and BL_SUFFIX
    # (regression test baseline directories) for REPRO or PROD runs
    if [[ ${MAKE_OPT^^} =~ "REPRO=Y" ]]; then
      RT_SUFFIX="_repro"
      BL_SUFFIX="_repro"
    else
      RT_SUFFIX=""
      BL_SUFFIX=""
    fi

    if [[ ${MAKE_OPT^^} =~ "WW3=Y" ]]; then
       COMPILE_PREV_WW3_NR=${COMPILE_NR}
    fi

    continue

  elif [[ $line == RUN* ]] ; then

    TEST_NAME=$(echo $line | cut -d'|' -f2 | sed -e 's/^ *//' -e 's/ *$//')
    MACHINES=$( echo $line | cut -d'|' -f3 | sed -e 's/^ *//' -e 's/ *$//')
    CB=$(       echo $line | cut -d'|' -f4)
    DEP_RUN=$(  echo $line | cut -d'|' -f5 | sed -e 's/^ *//' -e 's/ *$//')
    DATE_35D=$( echo $line | cut -d'|' -f6 | sed -e 's/^ *//' -e 's/ *$//')

    [[ -e "tests/$TEST_NAME" ]] || die "run test file tests/$TEST_NAME does not exist"
    [[ $CREATE_BASELINE == true && $CB != *fv3* ]] && continue

    if [[ ${MACHINES} != '' ]]; then
      if [[ ${MACHINES} == -* ]]; then
        [[ ${MACHINES} =~ ${MACHINE_ID} ]] && continue
      elif [[ ${MACHINES} == +* ]]; then
        [[ ${MACHINES} =~ ${MACHINE_ID} ]] || continue
      else
        echo "MACHINES=|${MACHINES}|"
        die "MACHINES spec must be either an empty string or start with either '+' or '-'"
      fi
    fi

    # 35 day tests
    [[ $TEST_35D == true ]] && rt_35d

    # Avoid uninitialized RT_SUFFIX/BL_SUFFIX (see definition above)
    RT_SUFFIX=${RT_SUFFIX:-""}
    BL_SUFFIX=${BL_SUFFIX:-""}

    if [[ $ROCOTO == true && $new_compile == true ]]; then
      new_compile=false
      in_metatask=true
      cat << EOF >> $ROCOTO_XML
  <metatask name="compile_${COMPILE_NR}_tasks"><var name="zero">0</var>
EOF
    fi

    TEST_NR=$( printf '%03d' $(( 10#$TEST_NR + 1 )) )

    (
      source ${PATHRT}/tests/$TEST_NAME

      NODES=$(( TASKS / TPN ))
      if (( NODES * TPN < TASKS )); then
        NODES=$(( NODES + 1 ))
      fi

      cat << EOF > ${RUNDIR_ROOT}/run_test_${TEST_NR}.env
      export JOB_NR=${JOB_NR}
      export MACHINE_ID=${MACHINE_ID}
      export RT_COMPILER=${RT_COMPILER}
      export RTPWD=${RTPWD}
      export INPUTDATA_ROOT=${INPUTDATA_ROOT}
      export INPUTDATA_ROOT_WW3=${INPUTDATA_ROOT_WW3}
      export INPUTDATA_ROOT_BMIC=${INPUTDATA_ROOT_BMIC}
      export PATHRT=${PATHRT}
      export PATHTR=${PATHTR}
      export NEW_BASELINE=${NEW_BASELINE}
      export CREATE_BASELINE=${CREATE_BASELINE}
      export RT_SUFFIX=${RT_SUFFIX}
      export BL_SUFFIX=${BL_SUFFIX}
      export SCHEDULER=${SCHEDULER}
      export ACCNR=${ACCNR}
      export QUEUE=${QUEUE}
      export PARTITION=${PARTITION}
      export ROCOTO=${ROCOTO}
      export ECFLOW=${ECFLOW}
      export REGRESSIONTEST_LOG=${REGRESSIONTEST_LOG}
      export LOG_DIR=${LOG_DIR}
      export DEP_RUN=${DEP_RUN}
EOF

      if [[ $ROCOTO == true ]]; then
        rocoto_create_run_task
      elif [[ $ECFLOW == true ]]; then
        ecflow_create_run_task
      else
        ./run_test.sh ${PATHRT} ${RUNDIR_ROOT} ${TEST_NAME} ${TEST_NR} ${COMPILE_NR} > ${LOG_DIR}/run_${TEST_NAME}${RT_SUFFIX}.log 2>&1
      fi
    )

    continue
  else
    die "Unknown command $line"
  fi
done < $TESTS_FILE

##
## run regression test workflow (currently Rocoto or ecFlow are supported)
##

if [[ $ROCOTO == true ]]; then
  if [[ $in_metatask == true ]]; then
    echo "  </metatask>" >> $ROCOTO_XML
  fi
  echo "</workflow>" >> $ROCOTO_XML
  # run rocoto workflow until done
  rocoto_run
fi

if [[ $ECFLOW == true ]]; then
  echo "endsuite" >> ${ECFLOW_RUN}/${ECFLOW_SUITE}.def
  # run ecflow workflow until done
  ecflow_run
fi

##
## regression test is either failed or successful
##
set +e
cat ${LOG_DIR}/compile_*_time.log              >> ${REGRESSIONTEST_LOG}
cat ${LOG_DIR}/rt_*.log                        >> ${REGRESSIONTEST_LOG}
if [[ -e fail_test ]]; then
  echo "FAILED TESTS: "
  echo "FAILED TESTS: "                        >> ${REGRESSIONTEST_LOG}
  while read -r failed_test_name
  do
    echo "Test ${failed_test_name} failed "
    echo "Test ${failed_test_name} failed "    >> ${REGRESSIONTEST_LOG}
  done < fail_test
   echo ; echo REGRESSION TEST FAILED
  (echo ; echo REGRESSION TEST FAILED)         >> ${REGRESSIONTEST_LOG}
else
   echo ; echo REGRESSION TEST WAS SUCCESSFUL
  (echo ; echo REGRESSION TEST WAS SUCCESSFUL) >> ${REGRESSIONTEST_LOG}

  rm -f fv3_*.x fv3_*.exe modules.fv3_*
  [[ ${KEEP_RUNDIR} == false ]] && rm -rf ${RUNDIR_ROOT}
  [[ ${ROCOTO} == true ]] && rm -f ${ROCOTO_XML} ${ROCOTO_DB} *_lock.db
  [[ ${TEST_35D} == true ]] && rm -f tests/cpld_bmark*_20*
  [[ ${SINGLE_NAME} != '' ]] && rm -f rt.conf.single
fi

date >> ${REGRESSIONTEST_LOG}

elapsed_time=$( printf '%02dh:%02dm:%02ds\n' $((SECONDS%86400/3600)) $((SECONDS%3600/60)) $((SECONDS%60)) )
echo "Elapsed time: ${elapsed_time}. Have a nice day!" >> ${REGRESSIONTEST_LOG}
echo "Elapsed time: ${elapsed_time}. Have a nice day!"
