#!/bin/bash

#~ND~FORMAT~MARKDOWN~
#~ND~START~
#
# # LongitudinalFreeSurferPipeline.sh
#
# ## Copyright Notice
#
# Copyright (C) 2015-2018 The Human Connectome Project/Connectome Coordination Facility
#
# * Washington University in St. Louis
# * Univeristy of Ljubljana
#
# ## Author(s)
#
# * Jure Demsar, Faculty of Computer and Information Science, University of Ljubljana
# * Matthew F. Glasser, Department of Anatomy and Neurobiology, Washington University in St. Louis
#
# ## Product
#
# [Human Connectome Project](http://www.humanconnectome.org) (HCP) Pipelines
#
# ## License
#
# See the [LICENSE](https://github.com/Washington-University/Pipelines/blob/master/LICENSE.md) file
#
#~ND~END~

# Configure custom tools
# - Determine if the PATH is configured so that the custom FreeSurfer v6 tools used by this script
#   (the recon-all.v6.hires script and other scripts called by the recon-all.v6.hires script)
#   are found on the PATH. If all such custom scripts are found, then we do nothing here.
#   If any one of them is not found on the PATH, then we change the PATH so that the
#   versions of these scripts found in ${HCPPIPEDIR}/FreeSurfer/custom are used.
configure_custom_tools()
{
  local which_recon_all
  local which_conf2hires
  local which_longmc

  which_recon_all=$(which recon-all.v6.hires)
  which_conf2hires=$(which conf2hires)
  which_longmc=$(which longmc)

  if [[ "${which_recon_all}" = "" || "${which_conf2hires}" == "" || "${which_longmc}" = "" ]] ; then
    export PATH="${HCPPIPEDIR}/FreeSurfer/custom:${PATH}"
    log_Warn "We were not able to locate one of the following required tools:"
    log_Warn "recon-all.v6.hires, conf2hires, or longmc"
    log_Warn ""
    log_Warn "To be able to run this script using the standard versions of these tools,"
    log_Warn "we added ${HCPPIPEDIR}/FreeSurfer/custom to the beginning of the PATH."
    log_Warn ""
    log_Warn "If you intended to use some other version of these tools, please configure"
    log_Warn "your PATH before invoking this script, such that the tools you intended to"
    log_Warn "use can be found on the PATH."
    log_Warn ""
    log_Warn "PATH set to: ${PATH}"
  fi  
}

# Show tool versions
show_tool_versions()
{
  # Show HCP pipelines version
  log_Msg "Showing HCP Pipelines version"
  ${HCPPIPEDIR}/show_version

  # Show recon-all version
  log_Msg "Showing recon-all.v6.hires version"
  local which_recon_all=$(which recon-all.v6.hires)
  log_Msg ${which_recon_all}
  recon-all.v6.hires -version
  
  # Show tkregister version
  log_Msg "Showing tkregister version"
  which tkregister
  tkregister -version

  # Show mri_concatenate_lta version
  log_Msg "Showing mri_concatenate_lta version"
  which mri_concatenate_lta
  mri_concatenate_lta -version

  # Show mri_surf2surf version
  log_Msg "Showing mri_surf2surf version"
  which mri_surf2surf
  mri_surf2surf -version

  # Show fslmaths location
  log_Msg "Showing fslmaths location"
  which fslmaths
}

validate_freesurfer_version()
{
  if [ -z "${FREESURFER_HOME}" ]; then
    log_Err_Abort "FREESURFER_HOME must be set"
  fi
  
  freesurfer_version_file="${FREESURFER_HOME}/build-stamp.txt"

  if [ -f "${freesurfer_version_file}" ]; then
    freesurfer_version_string=$(cat "${freesurfer_version_file}")
    log_Msg "INFO: Determined that FreeSurfer full version string is: ${freesurfer_version_string}"
  else
    log_Err_Abort "Cannot tell which version of FreeSurfer you are using."
  fi

  # strip out extraneous stuff from FreeSurfer version string
  freesurfer_version_string_array=(${freesurfer_version_string//-/ })
  freesurfer_version=${freesurfer_version_string_array[5]}
  freesurfer_version=${freesurfer_version#v} # strip leading "v"

  log_Msg "INFO: Determined that FreeSurfer version is: ${freesurfer_version}"

  # break FreeSurfer version into components
  # primary, secondary, and tertiary
  # version X.Y.Z ==> X primary, Y secondary, Z tertiary
  freesurfer_version_array=(${freesurfer_version//./ })

  freesurfer_primary_version="${freesurfer_version_array[0]}"
  freesurfer_primary_version=${freesurfer_primary_version//[!0-9]/}

  freesurfer_secondary_version="${freesurfer_version_array[1]}"
  freesurfer_secondary_version=${freesurfer_secondary_version//[!0-9]/}

  freesurfer_tertiary_version="${freesurfer_version_array[2]}"
  freesurfer_tertiary_version=${freesurfer_tertiary_version//[!0-9]/}

  if [[ $(( ${freesurfer_primary_version} )) -lt 6 ]]; then
    # e.g. 4.y.z, 5.y.z
    log_Err_Abort "FreeSurfer version 6.0.0 or greater is required. (Use FreeSurferPipeline-v5.3.0-HCP.sh if you want to continue using FreeSurfer 5.3)"
  fi
}

# Show usage information
show_usage()
{
  cat <<EOF

${g_script_name}: Run FreeSurfer processing pipeline

Usage: ${g_script_name}: PARAMETER...

PARAMETERs are: [ ] = optional; < > = user supplied value

  [--help] : show usage information and exit

  one from the following group is required

   --study_folder=<path to subject's data folder>
   --path=<path to subject's data folder>

  --subject=<subject ID>
  --sessions=<@ delimited list of session ids>
  --template-id=<ID of the created base template>

  [--seed=<recon-all seed value>]

  [--extra-reconall-arg-base=token] (repeatable)
      Generic single token (no whitespace) argument to pass to recon-all.
      Provides a mechanism to customize the recon-all command for base template preparation.
      The token itself may include dashes and equal signs (although Freesurfer doesn't currently use
         equal signs in its argument specification).
         e.g., [--extra-reconall-arg-base=-3T] is the correct syntax for adding the stand-alone "-3T" flag to recon-all.
               But, [--extra-reconall-arg-base="-norm3diters 3"] is NOT acceptable.
      For recon-all flags that themselves require an argument, you can handle that by specifying
         --extra-reconall-arg-base multiple times (in the proper sequential fashion).
         e.g., [--extra-reconall-arg-base=-norm3diters --extra-reconall-arg=3]
         will be translated to "-norm3diters 3" when passed to recon-all

  [--extra-reconall-arg-long=token] (repeatable)
      Generic single token (no whitespace) argument to pass to recon-all.
      Similar as above, except that it provides a mechanism to customize the recon-all command for the actual longitudinal processing.
EOF
}

get_options()
{
  local arguments=($@)
  # Note that the ($@) construction parses the arguments into an array of values using spaces as the delimiter

  # initialize global output variables
  unset p_study_folder
  unset p_subject
  unset p_sessions
  unset p_template_id
  unset p_seed
  unset p_extra_reconall_args_base
  unset p_extra_reconall_args_long

  # parse arguments
  local num_args=${#arguments[@]}
  local argument
  local index=0
  local extra_reconall_arg_base
  local extra_reconall_arg_long

  while [ "${index}" -lt "${num_args}" ]; do
    argument=${arguments[index]}

    case ${argument} in
      --help)
        show_usage
        exit 0
        ;;
      --path=*)
        p_study_folder=${argument#*=}
        index=$(( index + 1 ))
        ;;
      --study-folder=*)
        p_study_folder=${argument#*=}
        index=$(( index + 1 ))
        ;;
      --subject=*)
        p_subject=${argument#*=}
        index=$(( index + 1 ))
        ;;
      --template-id=*)
        p_template_id=${argument#*=}
        index=$(( index + 1 ))
        ;;
      --sessions=*)
        p_sessions=${argument#*=}
        index=$(( index + 1 ))
        ;;
      --seed=*)
        p_seed=${argument#*=}
        index=$(( index + 1 ))
        ;;
      --extra-reconall-arg-base=*)
        extra_reconall_arg_base=${argument#*=}
        p_extra_reconall_args_base+="${extra_reconall_arg_base} "
        index=$(( index + 1 ))
        ;;
      --extra-reconall-arg-long=*)
        extra_reconall_arg_long=${argument#*=}
        p_extra_reconall_args_long+="${extra_reconall_arg_long} "
        index=$(( index + 1 ))
        ;;
      *)
        show_usage
        log_Err_Abort "unrecognized option: ${argument}"
        ;;
    esac

  done

  local error_count=0

  # ------------------------------------------------------------------------------
  #  check required parameters
  # ------------------------------------------------------------------------------

  if [ -z "${p_study_folder}" ]; then
    log_Err "Study Folder (--path= or --study-folder=) required"
    error_count=$(( error_count + 1 ))
  else
    log_Msg "Study Folder: ${p_study_folder}"
  fi

  if [ -z "${p_subject}" ]; then
    log_Err "Subject (--subject=) required"
    error_count=$(( error_count + 1 ))
  else
    log_Msg "Subject: ${p_subject}"
  fi

  if [ -z "${p_sessions}" ]; then
    log_Err "Sessions (--sessions=) required"
    error_count=$(( error_count + 1 ))
  else
    log_Msg "Sessions: ${p_sessions}"
  fi

  if [ -z "${p_template_id}" ]; then
    log_Err "Template ID (--template-id=) required"
    error_count=$(( error_count + 1 ))
  else
    log_Msg "Template ID: ${p_template_id}"
  fi

  # show optional parameters if specified
  if [ ! -z "${p_seed}" ]; then
    log_Msg "Seed: ${p_seed}"
  fi
  if [ ! -z "${p_extra_reconall_args_base}" ]; then
    log_Msg "Extra recon-all base arguments: ${p_extra_reconall_args_base}"
  fi
  if [ ! -z "${p_extra_reconall_args_long}" ]; then
    log_Msg "Extra recon-all long arguments: ${p_extra_reconall_args_long}"
  fi

  if [ ${error_count} -gt 0 ]; then
    log_Err_Abort "For usage information, use --help"
  fi
}

main()
{
  local StudyFolder
  local SubjectID
  local Sessions
  local TemplateID
  local recon_all_seed
  local extra_reconall_args_base
  local extra_reconall_args_long

  # ----------------------------------------------------------------------
  log_Msg "Starting main functionality"
  # ----------------------------------------------------------------------

  # ----------------------------------------------------------------------
  log_Msg "Retrieve parameters"
  # ----------------------------------------------------------------------
  StudyFolder="${p_study_folder}"
  SubjectID="${p_subject}"
  Sessions="${p_sessions}"
  TemplateID="${p_template_id}"

  if [ ! -z "${p_seed}" ]; then
    recon_all_seed="${p_seed}"
  fi
  if [ ! -z "${p_extra_reconall_args_base}" ]; then
    extra_reconall_args_base="${p_extra_reconall_args_base}"
  fi
  if [ ! -z "${p_extra_reconall_args_long}" ]; then
    extra_reconall_args_long="${p_extra_reconall_args_long}"
  fi

  # ----------------------------------------------------------------------
  # Log values retrieved from positional parameters
  # ----------------------------------------------------------------------
  log_Msg "StudyFolder: ${StudyFolder}"
  log_Msg "SubjectID: ${SubjectID}"
  log_Msg "Sessions: ${Sessions}"
  log_Msg "TemplateID: ${TemplateID}"
  log_Msg "recon_all_seed: ${recon_all_seed}"
  log_Msg "extra_reconall_args_base: ${extra_reconall_args_base}"
  log_Msg "extra_reconall_args_long: ${extra_reconall_args_long}"

  # ----------------------------------------------------------------------
  log_Msg "Preparing the folder structure"
  # ----------------------------------------------------------------------
  Sessions=`echo ${Sessions} | sed 's/@/ /g'`
  log_Msg "After delimiter substitution, Sessions: ${Sessions}"
  LongDIR="${StudyFolder}/${SubjectID}.long.${TemplateID}/T1w"
  mkdir -p "${LongDIR}"
  for Session in ${Sessions} ; do
    Source="${StudyFolder}/${Session}/T1w/${Session}"
    Target="${LongDIR}/${Session}"
    log_Msg "Creating a link: ${Source} => ${Target}"
    ln -sf ${Source} ${Target}
  done

  # ----------------------------------------------------------------------
  log_Msg "Creating the base template: ${TemplateID}"
  # ----------------------------------------------------------------------
  # backup template dir if it exists
  if [ -d "${LongDIR}/${TemplateID}" ]; then
    TimeStamp=`date +%Y-%m-%d_%H.%M.%S.%6N`
    log_Msg "Base template dir: ${LongDIR}/${TemplateID} already exists, backing up to ${LongDIR}/${TemplateID}.${TimeStamp}"
    mv ${LongDIR}/${TemplateID} ${LongDIR}/${TemplateID}.${TimeStamp}
  fi

  recon_all_cmd="recon-all.v6.hires"
  recon_all_cmd+=" -sd ${LongDIR}"
  recon_all_cmd+=" -base ${TemplateID}"
  for Session in ${Sessions} ; do
    recon_all_cmd+=" -tp ${Session}"
  done
  recon_all_cmd+=" -all"

  if [ ! -z "${recon_all_seed}" ]; then
    recon_all_cmd+=" -norandomness -rng-seed ${recon_all_seed}"
  fi

  if [ ! -z "${extra_reconall_args_base}" ]; then
    recon_all_cmd+=" ${extra_reconall_args_base}"
  fi

  log_Msg "...recon_all_cmd: ${recon_all_cmd}"
  ${recon_all_cmd}
  return_code=$?
  if [ "${return_code}" != "0" ]; then
    log_Err_Abort "recon-all command failed with return_code: ${return_code}"
  fi

  # ----------------------------------------------------------------------
  log_Msg "Running the longitudinal recon-all"
  # ----------------------------------------------------------------------
  for Session in ${Sessions} ; do
    log_Msg "Running longitudinal recon all for session: ${Session}"
    recon_all_cmd="recon-all.v6.hires"
    recon_all_cmd+=" -sd ${LongDIR}"
    recon_all_cmd+=" -long ${Session} ${TemplateID} -all"
    if [ ! -z "${extra_reconall_args_long}" ]; then
      recon_all_cmd+=" ${extra_reconall_args_long}"
    fi
    log_Msg "...recon_all_cmd: ${recon_all_cmd}"
    ${recon_all_cmd}
    return_code=$?
    if [ "${return_code}" != "0" ]; then
      log_Err_Abort "recon-all command failed with return_code: ${return_code}"
    fi

    log_Msg "Organizing the folder structure for: ${Session}"
    # create the symlink
    TargetDIR="${StudyFolder}/${Session}.long.${TemplateID}/T1w"
    mkdir -p "${TargetDIR}"
    ln -sf "${LongDIR}/${Session}.long.${TemplateID}" "${TargetDIR}/${Session}.long.${TemplateID}"
  done

  # ----------------------------------------------------------------------
  log_Msg "Cleaning up the folder structure"
  # ----------------------------------------------------------------------
  for Session in ${Sessions} ; do
    # remove the symlink in the subject's folder
    rm -rf "${LongDIR}/${Session}"
  done

  # ----------------------------------------------------------------------
  log_Msg "Completing main functionality"
  # ----------------------------------------------------------------------
}

# Global processing - everything above here should be in a function
g_script_name=$(basename "${0}")

# Allow script to return a Usage statement, before any other output or checking
if [ "$#" = "0" ]; then
    show_usage
    exit 1
fi

# ------------------------------------------------------------------------------
#  Check that HCPPIPEDIR is defined and Load Function Libraries
# ------------------------------------------------------------------------------
if [ -z "${HCPPIPEDIR}" ]; then
  echo "${g_script_name}: ABORTING: HCPPIPEDIR environment variable must be set"
  exit 1
fi

source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@"         # Debugging functions; also sources log.shlib
source ${HCPPIPEDIR}/global/scripts/opts.shlib                 # Command line option functions
source ${HCPPIPEDIR}/global/scripts/processingmodecheck.shlib  # Check processing mode requirements

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
  show_usage
  exit 0
fi

${HCPPIPEDIR}/show_version

# ------------------------------------------------------------------------------
#  Verify required environment variables are set and log value
# ------------------------------------------------------------------------------
log_Check_Env_Var HCPPIPEDIR
log_Check_Env_Var FREESURFER_HOME

# Platform info
log_Msg "Platform Information Follows: "
uname -a

# Configure the use of FreeSurfer v6 custom tools
configure_custom_tools

# Show tool versions
show_tool_versions

# Validate version of FreeSurfer in use
validate_freesurfer_version

# Determine whether named or positional parameters are used
if [[ ${1} == --* ]]; then
  # Named parameters (e.g. --parameter-name=parameter-value) are used
  log_Msg "Using named parameters"

  # Get command line options
  get_options "$@"

  # Invoke main functionality using positional parameters
  #     ${1}               ${2}           ${3}             ${4}             ${5}             ${6}
  main "${p_study_folder}" "${p_subject}" "${p_t1w_image}" "${p_t1w_brain}" "${p_t2w_image}" "${p_seed}"
else
  # Positional parameters are used but not supported
  log_Msg "Positional parameters are not supported!"
fi

log_Msg "Completed!"
exit 0
