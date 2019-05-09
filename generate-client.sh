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
	   Generates client certificate files signed by this CA in
	   clients/ID folder

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
	CLIENTID="${1}"
	OUTPUT=`readlink -f "clients/${1}"`
	[ ! -d "${OUTPUT}" ] && mkdir -p "${OUTPUT}"
	[ "$(ls -A "${OUTPUT}")" ] && echo "Warning: Destination directory not empty"
else
	print_help
	exit 1
fi

# Delete the intermediate directory on failure
trap 'on_failure $OUTPUT' ERR

pushd "${OUTPUT}" >/dev/null

message "Generating private key ($OUTPUT/$CLIENTID.pem)"
# TODO prompt for passphrase if cli option
#prompt_and_store_passphrase private/passphrase
openssl genrsa -out ${CLIENTID}.key.pem 2048
chmod 400 ${CLIENTID}.key.pem

message "Generating Certificate signing request"
# TODO append custom openssl config with SAN and extensions
# switch the default signing-ca openssl.cnf with user specified file/folder
openssl req -config ${SIGNING_CA_DIR}/openssl.cnf -new -sha256 \
      -key ${CLIENTID}.key.pem -out ${CLIENTID}.csr.pem

# TODO message displays the CN of the signing CA
message "Signing client certificate (certs/intermediate.cert.pem)"
openssl ca -config ${SIGNING_CA_DIR}/openssl.cnf -extensions user_cert \
      -days 365 -notext -md sha256 \
      -in ${CLIENTID}.csr.pem -out ${CLIENTID}.cert.pem

chmod 444 ${CLIENTID}.cert.pem

message "${CLIENTID} certificate:"
openssl x509 -noout -text \
	-certopt no_pubkey -certopt no_sigdump \
	-nameopt multiline \
	-in ${CLIENTID}.cert.pem

message "Verifying client certificate"
openssl verify -CAfile ${SIGNING_CA_DIR}/certs/ca-chain.cert.pem ${CLIENTID}.cert.pem

ln -s ${SIGNING_CA_DIR}/certs/ca-chain.cert.pem ca-chain.cert.pem

# TODO generate p12 bundle

popd >/dev/null
