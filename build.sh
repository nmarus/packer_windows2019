#!/usr/bin/env bash

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TEMP_DIR=/tmp

show_help() {
  echo -e "\nUsage:"
  echo "  ./build.sh <local|esxi|vcenter>"
}

# parse args (if $1 is null)
if [ -z ${1+x} ]; then
  echo -e "Error: Missing required argument!"
  show_help
  exit 1
else
  BUILDER_TYPE=${1}
  BUILDER_VARS=${PROJECT_DIR}/${BUILDER_TYPE}-config.json
fi

# validate build target
if [[ "${BUILDER_TYPE}" != "local" ]] && [[ "${BUILDER_TYPE}" != "esxi" ]] && [[ "${BUILDER_TYPE}" != "vcenter" ]]; then
  echo -e "Error: Invalid build target \"${BUILDER_TYPE}\""
  show_help
  exit 1
fi

# define file paths
PACKER_VM_NAME=windows_server_2019
PACKER_CONFIG_DIR=${PROJECT_DIR}/packer
PACKER_OUTPUT_DIR=${PROJECT_DIR}/output-vmware-iso
PACKER_MAIN=${PACKER_CONFIG_DIR}/${BUILDER_TYPE}-provision.json
PACKER_VARS=${PROJECT_DIR}/vars.json

BUILDER_DIR=${PROJECT_DIR}/__${PACKER_VM_NAME}

VMX_DIR=${BUILDER_DIR}/output-vmware-vmx
VMX_FILE=${VMX_DIR}/${PACKER_VM_NAME}.vmx

OVF_DIR=${BUILDER_DIR}/output-vmware-ovf
OVF_FILE=${OVF_DIR}/${PACKER_VM_NAME}.ovf
OVF_MANIFEST=${OVF_DIR}/${PACKER_VM_NAME}.mf

OVF_OPTION_XML=${PROJECT_DIR}/ovf/options.xml
OVF_OPTION_INSERT_BEFORE=VirtualHardwareSection

OVA_FILE=${BUILDER_DIR}/${PACKER_VM_NAME}.ova

# validate PACKER_MAIN exists
if [ ! -f ${PACKER_MAIN} ]; then
  echo -e "Recipe not found at ${PACKER_MAIN}!"
  exit 1
fi

# validate PACKER_VARS path exists
if [ ! -f ${PACKER_VARS} ]; then
  echo -e "Recipe vars not found at ${PACKER_VARS}!"
  exit 1
fi

# export vars and run packer
export PACKER_VM_NAME=${PACKER_VM_NAME}
export PACKER_CONFIG_DIR=${PACKER_CONFIG_DIR}
export PACKER_UNATTEND_DIR=${PROJECT_DIR}/unattend
export PACKER_SCRIPTS_DIR=${PROJECT_DIR}/scripts
export PACKER_INSTALLS_DIR=${PROJECT_DIR}/installs

# run from ${PROJECT_DIR} dir
pushd ${PROJECT_DIR} &> /dev/null
# check for optional BUILDER_VARS
if [ -f ${BUILDER_VARS} ]; then
  packer build -var-file ${BUILDER_VARS} -var-file ${PACKER_VARS} ${PACKER_MAIN}
else
  packer build -var-file ${PACKER_VARS} ${PACKER_MAIN}
fi
# return to previous working dir
popd &> /dev/null

# reset build directory
rm -rf ${BUILDER_DIR}
mkdir -p ${BUILDER_DIR}

# post process by builder type
if [[ "${BUILDER_TYPE}" == "local" ]]; then
  # create vmx dir
  mv ${PACKER_OUTPUT_DIR} ${VMX_DIR}
  # create ovf dir
  mkdir -p ${OVF_DIR}
  # convert vmx to ovf
  ovftool ${VMX_FILE} ${OVF_FILE}
elif [[ "${BUILDER_TYPE}" == "esxi" ]]; then
  # create ovf dir
  mv ${PACKER_OUTPUT_DIR}/${PACKER_VM_NAME} ${OVF_DIR}
  rm -rf ${PACKER_OUTPUT_DIR}
elif [[ "${BUILDER_TYPE}" == "vcenter" ]]; then
  # create ovf dir
  mv ${PACKER_OUTPUT_DIR} ${OVF_DIR}
fi

# update ovf if options file found
if [ -f ${OVF_OPTION_XML} ]; then
  # modify ovf
  awk '/\'${OVF_OPTION_INSERT_BEFORE}'/{while(getline line<"'${OVF_OPTION_XML}'"){print line}} //' ${OVF_FILE} > ${TEMP_DIR}/_temp.ovf
  mv ${TEMP_DIR}/_temp.ovf ${OVF_FILE}

  # update sha256 in manifest
  SHA256=$(shasum -a 256 ${OVF_FILE} | awk '{print $1}')
  sed -i '' -e 's/\(SHA256('${PACKER_VM_NAME}'.ovf)= \).*/\1'${SHA256}'/g' ${OVF_MANIFEST}
fi

# convert from ovf to ova
ovftool ${OVF_FILE} ${OVA_FILE}

# cleanup
rm -rf ${PACKER_OUTPUT_DIR}
