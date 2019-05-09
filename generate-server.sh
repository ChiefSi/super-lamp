#!/bin/bash -e

function on_failure()
{
	rm -rf "${1}"
}

function message()
{
	printf '\e[1m\e[38;5;27m%s\e[0m\n' "${1}"
}

function print_help()
{
	cat <<EOF
Usage: $0 <ID> [-h|--help]
	   Generates server certificate files signed by this CA in
	   servers/ID folder

EOF
}

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
POSITIONAL=()
SIGNING_CA_DIR="${DIR}"

while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-h|--help)
			shift
			print_help
			exit 0
		;;
		*)
			POSITIONAL+=("$1")
			shift
		;;
	esac
done

set -- "${POSITIONAL[@]}"

OUTPUT=
if [ $# -ge 1 ]; then
	SERVERID="${1}"
	OUTPUT=`readlink -f "servers/${1}"`
	[ ! -d "${OUTPUT}" ] && mkdir -p "${OUTPUT}"
	[ "$(ls -A "${OUTPUT}")" ] && echo "Warning: Destination directory not empty"
else
	print_help
	exit 1
fi

# Delete the intermediate directory on failure
trap 'on_failure $OUTPUT' ERR

pushd "${OUTPUT}" >/dev/null

message "Generating private key ($OUTPUT/$SERVERID.pem)"
# TODO prompt for passphrase if cli option
#prompt_and_store_passphrase private/passphrase
openssl genrsa -out ${SERVERID}.key.pem 2048
chmod 400 ${SERVERID}.key.pem

message "Generating Certificate signing request"
# TODO append custom openssl config with SAN and extensions
openssl req -config ${SIGNING_CA_DIR}/openssl.cnf -new -sha256 \
      -key ${SERVERID}.key.pem -out ${SERVERID}.csr.pem

# TODO message displays the CN of the signing CA
message "Signing client certificate (certs/intermediate.cert.pem)"
openssl ca -config ${SIGNING_CA_DIR}/openssl.cnf -extensions server_cert \
      -days 365 -notext -md sha256 \
      -in ${SERVERID}.csr.pem -out ${SERVERID}.cert.pem

chmod 444 ${SERVERID}.cert.pem

message "${SERVERID} certificate:"
openssl x509 -noout -text \
	-certopt no_pubkey -certopt no_sigdump \
	-nameopt multiline \
	-in ${SERVERID}.cert.pem

message "Verifying client certificate"
openssl verify -CAfile ${SIGNING_CA_DIR}/certs/ca-chain.cert.pem ${SERVERID}.cert.pem

ln -s ${SIGNING_CA_DIR}/certs/ca-chain.cert.pem ca-chain.cert.pem


popd >/dev/null
