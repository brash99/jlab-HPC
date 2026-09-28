#!/bin/bash

# ------------------------------------------------------------------------- #
# This script runs real data replay jobs for GMn/nTPE data. It was created  #
# based on Andrew Puckett's script.                                         #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

#SBATCH --partition=production
#SBATCH --account=halla
#SBATCH --mem-per-cpu=4000

# List of arguments
runnum=$1
maxevents=$2
firstevent=$3
prefix=$4
firstsegment=$5
maxsegments=$6
datadir=$7
outdirpath=$8
run_on_ifarm=${9}
analyzerenv=${10}
sbsofflineenv=${11}
sbsreplayenv=${12}
ANAVER=${13}     # Analyzer version
useJLABENV=${14} # Use 12gev_env instead of modulefiles?
JLABENV=${15}    # /site/12gev_phys/softenv.sh version

# paths to necessary libraries (ONLY User specific part) ---- #
export ANALYZER=$analyzerenv
export SBSOFFLINE=$sbsofflineenv
export SBS_REPLAY=$sbsreplayenv
export DATA_DIR=$datadir
# ----------------------------------------------------------- #

ifarmworkdir=${PWD}
if [[ $run_on_ifarm == 1 ]]; then
    SWIF_JOB_WORK_DIR=$ifarmworkdir
fi
echo 'Work directory = '$SWIF_JOB_WORK_DIR

# Enabling module
MODULES=/etc/profile.d/modules.sh 
if [[ $(type -t module) != function && -r ${MODULES} ]]; then 
    source ${MODULES} 
fi 
# Choosing software environment
### Should be able to comment out, since also set in setenv.sh script ####
if [[ (! -d /group/halla/modulefiles) || ($useJLABENV -eq 1) ]]; then 
    source /site/12gev_phys/softenv.sh $JLABENV
    source $ANALYZER/bin/setup.sh
else 
    module use /group/halla/modulefiles
    module load analyzer/$ANAVER
    module list
fi

# setup analyzer specific environments
export ANALYZER_CONFIGPATH=$SBS_REPLAY/replay
source $SBSOFFLINE/bin/sbsenv.sh

export DB_DIR=$SBS_REPLAY/DB
export OUT_DIR=$SWIF_JOB_WORK_DIR
export LOG_DIR=$SWIF_JOB_WORK_DIR

echo 'OUT_DIR='$OUT_DIR
echo 'LOG_DIR='$LOG_DIR

# Select the replay entry point. The default remains the historical CDet-only
# replay. run-cdet-gem-replay.sh sets CDET_ENABLE_GEMS=1 to select the full
# GEp replay, including gemFT, gemFPP, FTROI, and GEM tracking.
CDET_ENABLE_GEMS=${CDET_ENABLE_GEMS:-0}

if [[ ${CDET_ENABLE_GEMS} -eq 1 ]]; then
    REPLAY_MACRO="${SBS_REPLAY}/replay/replay_gep.C"
    REPLAY_FUNCTION="replay_gep"
    DOGEMS=1
    OUTPUT_GLOB="${OUT_DIR}/gep5_replayed_${runnum}_*.root"
else
    REPLAY_MACRO="${SBS_REPLAY}/replay/replay_CDet.C"
    REPLAY_FUNCTION="replay_CDet"
    # Preserve replay_CDet's historical default argument exactly. The current
    # macro does not act on this parameter, but callers should not observe an
    # argument-level behavior change if that implementation later evolves.
    DOGEMS=1
    OUTPUT_GLOB="${OUT_DIR}/cdet_${runnum}_*.root"
fi

if [[ ! -f "${REPLAY_MACRO}" ]]; then
    echo "ERROR: Replay macro not found:"
    echo "  ${REPLAY_MACRO}"
    exit 1
fi

# Every job gets a separate ACLiC directory.
#
# SWIF_JOB_WORK_DIR should already be unique for each SWIF job. Including
# the process ID also protects local/ifarm runs started in the same directory.
ACLIC_DIR="${SWIF_JOB_WORK_DIR}/aclic_${runnum}_${firstsegment}_$$"
ROOT_DRIVER="${SWIF_JOB_WORK_DIR}/run_replay_${runnum}_${firstsegment}_$$.C"

mkdir -p "${ACLIC_DIR}"

# ------------------------------------------------------------------------- #
# Handle .rootrc
# ------------------------------------------------------------------------- #

ROOTRC_BACKUP=""

cleanup()
{
    status=$?

    rm -f "${ROOT_DRIVER}"
    rm -rf "${ACLIC_DIR}"

    if [[ -f "${SWIF_JOB_WORK_DIR}/.rootrc" ]]; then
        rm -f "${SWIF_JOB_WORK_DIR}/.rootrc"
    fi

    if [[ -n "${ROOTRC_BACKUP}" &&
          -f "${ROOTRC_BACKUP}" ]]; then
        mv "${ROOTRC_BACKUP}" "${SWIF_JOB_WORK_DIR}/.rootrc"
    fi

    exit "${status}"
}

trap cleanup EXIT

if [[ -f "${SWIF_JOB_WORK_DIR}/.rootrc" ]]; then
    ROOTRC_BACKUP="${SWIF_JOB_WORK_DIR}/.rootrc.original.$$"
    mv "${SWIF_JOB_WORK_DIR}/.rootrc" "${ROOTRC_BACKUP}"
fi

cp "${SBS}/run_replay_here/.rootrc" \
   "${SWIF_JOB_WORK_DIR}/.rootrc"

# ------------------------------------------------------------------------- #
# Build a small ROOT driver macro
#
# Important:
#   SetBuildDir() is called before loading the selected replay macro.
#   Therefore all ACLiC-generated files go into this job's private directory,
#   not into the shared SBS_REPLAY/replay directory.
# ------------------------------------------------------------------------- #

cat > "${ROOT_DRIVER}" <<EOF
{
    gSystem->SetBuildDir("${ACLIC_DIR}", kTRUE);

    const char* replayMacro =
        "${REPLAY_MACRO}+";

    Long_t loadStatus =
        gROOT->ProcessLine(TString::Format(".L %s", replayMacro));

    if (loadStatus != 0) {
        Error("run_replay", "Failed to compile/load %s", replayMacro);
        gSystem->Exit(1);
    }

    ${REPLAY_FUNCTION}(
        ${runnum},
        ${maxevents},
        ${firstevent},
        "${prefix}",
        ${firstsegment},
        ${maxsegments},
        2,
        0,
        0,
        0,
        ${DOGEMS},
        0,
        0
    );
}
EOF

echo "ROOT driver macro:"
echo "  ${ROOT_DRIVER}"

echo "Job-local ACLiC directory:"
echo "  ${ACLIC_DIR}"

# ------------------------------------------------------------------------- #
# Run Analyzer
# ------------------------------------------------------------------------- #

analyzer -b -q "${ROOT_DRIVER}"

# ------------------------------------------------------------------------- #
# Copy output files
# ------------------------------------------------------------------------- #

mkdir -p "${outdirpath}/rootfiles"

shopt -s nullglob

output_files=( ${OUTPUT_GLOB} )

if (( ${#output_files[@]} == 0 )); then
    echo "ERROR: No replay output files were produced for run ${runnum}."
    exit 1
fi

echo "Copying output files:"

for output_file in "${output_files[@]}"; do
    echo "  ${output_file}"
    cp "${output_file}" "${outdirpath}/rootfiles/"
done
