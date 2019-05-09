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
Usage: $0 <DIRECTORY> [-h|--help]
	   Generates intermediate ca files/scripts for this Root CA in
	   intermediates/DIRECTORY

EOF
}

function prompt_and_store_passphrase()
{
    DEST="${1}"
    ATTEMPT=0
    while [ $ATTEMPT -lt 3 ]; do

        echo -n "Enter passphrase: "
        read -s PASS1
        echo

        echo -n "Confirm passphrase: "
        read -s PASS2
        echo

        if [ ${PASS1} = ${PASS2} ]; then
            echo "${PASS1}" > "${DEST}"
            break
        else
            echo "Passwords do not match"
            ATTEMPT=$[$ATTEMPT+1]
            [ $ATTEMPT -gt 3 ] && exit 1
        fi
    done
}

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
POSITIONAL=()
SIGNING_CA_DIR="${DIR}"
INTERMEDIATE_SSL_CNF="${DIR}/templates/intermediate.cnf.in"
GENERATE_INTERMEDIATE_SCRIPT=`readlink -f ${BASH_SOURCE[0]}`
GENERATE_CLIENT_SCRIPT="${DIR}/generate-client.sh"
GENERATE_SERVER_SCRIPT="${DIR}/generate-server.sh"

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
	OUTPUT=`readlink -f "intermediates/${1}"`
	[ ! -d "${OUTPUT}" ] && mkdir -p "${OUTPUT}"
	[ "$(ls -A "${OUTPUT}")" ] && echo "Warning: Destination directory not empty"
else
	print_help
	exit 1
fi

# Delete the intermediate directory on failure
trap 'on_failure $OUTPUT' ERR

pushd "${OUTPUT}" >/dev/null

mkdir certs crl csr intermediates newcerts private servers clients
chmod 700 private
touch index.txt
echo 1000 > serial
echo 1000 > crlnumber

sed "s#%{DIRECTORY}#${OUTPUT}#g" "${INTERMEDIATE_SSL_CNF}" > openssl.cnf
cp "${GENERATE_INTERMEDIATE_SCRIPT}" generate-intermediate-ca.sh
cp "${GENERATE_CLIENT_SCRIPT}" generate-client.sh
cp "${GENERATE_SERVER_SCRIPT}" generate-server.sh
mkdir templates
cp "${INTERMEDIATE_SSL_CNF}" templates/

message "Generating CA private key (private/intermediate.key.pem)"
prompt_and_store_passphrase private/passphrase
openssl genrsa -aes256 -out private/intermediate.key.pem -passout file:private/passphrase 4096
chmod 400 private/intermediate.key.pem

message "Generating Certificate signing request"
openssl req -config openssl.cnf -new -sha256 \
      -key private/intermediate.key.pem \
      -out csr/intermediate.csr.pem

message "Signing intermediate certificate (certs/intermediate.cert.pem)"
openssl ca -config ${SIGNING_CA_DIR}/openssl.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in csr/intermediate.csr.pem \
      -out certs/intermediate.cert.pem

chmod 444 certs/intermediate.cert.pem

message "Intermiediate certificate:"
openssl x509 -noout -text \
	-certopt no_pubkey -certopt no_sigdump \
	-nameopt multiline \
	-in certs/intermediate.cert.pem

message "Verifying intermediate certificate"
openssl verify -CAfile ${SIGNING_CA_DIR}/certs/ca-chain.cert.pem certs/intermediate.cert.pem

cat certs/intermediate.cert.pem ${SIGNING_CA_DIR}/certs/ca-chain.cert.pem > certs/ca-chain.cert.pem
chmod 444 certs/ca-chain.cert.pem

popd >/dev/null
