#!/bin/bash

SDIR=$(dirname "$0")
source $SDIR/env.sh
export RUN_SUMPATH=/data/logs/orderer.log
export RUN_FRONTEND=/data/logs/frontend.log

function enrollCAAdmin() {
	logr "Enrolling with $ENROLLMENT_URL as bootstrap identity ..."
	fabric-ca-client enroll -d -u $ENROLLMENT_URL
}

# Register any identities associated with a peer
function registerOrdererIdentities() {
	enrollCAAdmin

	fabric-ca-client register -d --id.name $CORE_PEER_ID --id.secret $ORDERER_PASS --id.type orderer --id.affiliation $ORG

	logr "Registering admin identity with $ADMIN_NAME:$ADMIN_PASS"
	# The admin identity has the "admin" attribute which is added to ECert by default
	fabric-ca-client register -d --id.name $ADMIN_NAME --id.secret $ADMIN_PASS --id.attrs "admin=true:ecert" --id.affiliation $ORG
}

function getCACerts() {
	logr "Getting CA certificates ..."
	logr "Getting CA certs for organization $ORG and storing in $ORG_MSP"
	mkdir -p $ORG_MSP
	fabric-ca-client getcacert -d -u $ENROLLMENT_URL -M $ORG_MSP
	mkdir -p $ORG_MSP/tlscacerts
	cp $ORG_MSP/cacerts/* $ORG_MSP/tlscacerts

	# Copy CA cert
	mkdir -p $FABRIC_CA_CLIENT_HOME/msp/tlscacerts
	cp $ORG_MSP/cacerts/* $FABRIC_CA_CLIENT_HOME/msp/tlscacerts
}

function main() {
	logr "wait for ca server"
	sleep 20

	mkdir -p FABRIC_CA_CLIENT_HOME

	registerOrdererIdentities
	getCACerts
	logr "Finished create certificates"
	logr "Start create TLS"

	logr "Enroll again to get the orderer's enrollment certificate (default profile)"
	genMSPCerts $CORE_PEER_ID $CORE_PEER_ID $ORDERER_PASS $ORG $CA_HOST $ORDERER_CERT_DIR/msp

	mkdir -p $ORDERER_CERT_DIR/tls
	cp $ORDERER_CERT_DIR/msp/signcerts/* $ORDERER_GENERAL_TLS_CERTIFICATE
	cp $ORDERER_CERT_DIR/msp/keystore/* $ORDERER_GENERAL_TLS_PRIVATEKEY

	if [ $ADMINCERTS ]; then
		logr "Generate client TLS cert and key pair for the peer CLI"
		genMSPCerts $CORE_PEER_ID $ADMIN_NAME $ADMIN_PASS $ORG $CA_HOST $ADMIN_CERT_DIR/msp

		cp $ADMIN_CERT_DIR/msp/signcerts/* $ADMIN_CERT_DIR/tls/client.crt
		cp $ADMIN_CERT_DIR/msp/keystore/* $ADMIN_CERT_DIR/tls/client.key
		mkdir -p $ADMIN_CERT_DIR/msp/admincerts
		cp $ADMIN_CERT_DIR/msp/signcerts/* $ADMIN_CERT_DIR/msp/admincerts/cert.pem
		logr "Copy the org's admin cert into some target MSP directory"

		mkdir -p $ORDERER_CERT_DIR/msp/admincerts
		cp $ADMIN_CERT_DIR/msp/signcerts/* $ORDERER_CERT_DIR/msp/admincerts/cert.pem

		mkdir -p $ORG_MSP/admincerts
		cp $ADMIN_CERT_DIR/msp/signcerts/* $ORG_MSP/admincerts/admin-cert.pem
		cp $ORDERER_CERT_DIR/msp/signcerts/* $ORG_MSP/admincerts/orderer-cert.pem
	fi

	logr "Finished create TLS"

	cp /config/orderer.yaml $FABRIC_CFG_PATH/orderer.yaml

	logr "wait for genesis block and replicas"
	sleep 50

	logr "Start frontend"
	cd $GOPATH/src/github.com/hyperledger/fabric-orderingservice
	rm -rf config/currentView
	cp /config/hosts.config config/hosts.config
	cp /config/node.config config/node.config
	./startFrontend.sh 1000 10 9999 2>&1 | tee -a $RUN_FRONTEND &

	logr "Wait for genesis block and bft"
	sleep 20

	logr "Start orderer"
	orderer start 2>&1 | tee -a $RUN_SUMPATH 
}

main
