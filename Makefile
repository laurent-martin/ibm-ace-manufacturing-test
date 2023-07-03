# Makefile

# configuration is placed here
PRIVATEDIR=private

# generated files are placed here
OUTDIR=generated

# source files, scripts
SCRIPTDIR=script

# GNU tar is needed
# on mac: TAR=gtar make -e
TAR=tar

# get config parameters
include $(OUTDIR)/configuration.mak

# default target
all::

###################################
# Config file
# generate initial empty config from template
$(PRIVATEDIR)/configuration.env:
	mkdir -p $(PRIVATEDIR)
	@if test -e $(PRIVATEDIR)/configuration.env;then echo 'ERROR: conf file already exists: $@';exit 1;fi
	cp script/configuration.tmpl.env $@

$(OUTDIR)/configuration.mak: $(PRIVATEDIR)/configuration.env
	mkdir -p $(OUTDIR)
	sed 's/{/(/g;s/}/)/g' < $< > $@

init: $(PRIVATEDIR)/configuration.env
	@echo Done.

# create config template from custom config (when parameters are added)
template:
	sed -Ee 's/(_key|_address)=.*/\1=_your_value_here_/' < $(PRIVATEDIR)/configuration.env > $(SCRIPTDIR)/configuration.tmpl.env

clean::
	rm -fr $(OUTDIR)


###################################
# Client certificate
all:: $(OUTDIR)/$(cert_p12)
$(OUTDIR)/$(cert_p12) $(OUTDIR)/$(cert_pem): $(SCRIPTDIR)/ssl.tmpl
	$(SCRIPTDIR)/generate_certificate.sh $(OUTDIR) $(SCRIPTDIR)/ssl.tmpl

###################################
# Documentation
%.pdf: %.md
	pandoc \
	  --standalone --from=gfm --to=pdf --pdf-engine=xelatex \
	  --resource-path=.. --toc --number-sections \
	  --shift-heading-level-by=-1 \
	  --variable=include-before:'\newpage' --variable=documentclass:report \
	  --variable=date:$$(date '+%Y/%m/%d') --variable=author:'Laurent MARTIN' \
	  --variable=mainfont:Arial --variable=urlcolor:blue --variable=geometry:margin=15mm \
	  -o $@ $<

all:: doc

doc: README.pdf

#clean::
#	rm -f README.pdf

###################################
# OPCUA Simulator

OPC_ARCHIVE_LIST=\
	$(SCRIPTDIR)/create_container_opcplc.sh \
	$(PRIVATEDIR)/configuration.env \
	$(OUTDIR)/$(cert_pem)
OPC_ARCHIVE_FILE=opc_server_files.tgz
OPC_HOST_FOLDER=opc_files

# build files to send to opc simulator
build_opcplc: $(OUTDIR)/$(OPC_ARCHIVE_FILE)
# GNU tar required here
$(OUTDIR)/$(OPC_ARCHIVE_FILE): $(OPC_ARCHIVE_LIST)
	chmod a+x $(SCRIPTDIR)/create_container_opcplc.sh
	$(TAR) -c -v -z -f $@ --transform='s|.*/||' $(OPC_ARCHIVE_LIST)
# send files to simulator host
deploy_opcplc: $(OUTDIR)/$(OPC_ARCHIVE_FILE)
	scp $(OUTDIR)/$(OPC_ARCHIVE_FILE) $(opcua_server_address):
	ssh $(opcua_server_address) 'rm -fr $(OPC_HOST_FOLDER) && mkdir -p $(OPC_HOST_FOLDER) && tar --directory=$(OPC_HOST_FOLDER) -x -v -z -f $(OPC_ARCHIVE_FILE) && rm -f $(OPC_ARCHIVE_FILE)'
ssh_opcplc:
	ssh $(opcua_server_address)

###################################
# ACE

ACE_ARCHIVE_LIST=\
	$(SCRIPTDIR)/ace_container_tools.rc.sh \
	$(SCRIPTDIR)/prepare_ace_workdir.sh \
	$(SCRIPTDIR)/server.conf.tmpl.yaml \
	$(SCRIPTDIR)/generate_var_list_property.py \
	$(PRIVATEDIR)/configuration.env \
	$(PRIVATEDIR)/$(acmfg_tar) \
	$(OUTDIR)/$(cert_pem) \
	$(OUTDIR)/$(cert_p12)
ACE_ARCHIVE_FILE=ace_server_files.tgz
ACE_HOST_FOLDER=ace_files

# generate files to integration server host
build_ace: $(OUTDIR)/$(ACE_ARCHIVE_FILE)
# build a flat archive with files to transfer
$(OUTDIR)/$(ACE_ARCHIVE_FILE): $(ACE_ARCHIVE_LIST)
	chmod a+x $(SCRIPTDIR)/prepare_ace_workdir.sh $(SCRIPTDIR)/generate_var_list_property.py
	$(TAR) -c -v -z -f $@ --transform='s|.*/||' $(ACE_ARCHIVE_LIST)
# send files to ace host
deploy_ace: $(OUTDIR)/$(ACE_ARCHIVE_FILE)
	scp $(OUTDIR)/$(ACE_ARCHIVE_FILE) $(ace_server_address):
	ssh $(ace_server_address) "rm -fr $(ACE_HOST_FOLDER) && mkdir -p $(ACE_HOST_FOLDER) && tar --directory=$(ACE_HOST_FOLDER) -x -v -z -f $(ACE_ARCHIVE_FILE) && rm -f $(ACE_ARCHIVE_FILE)"
ssh_ace:
	ssh $(ace_server_address)

###################################
# Mosquitto
MQTT_ARCHIVE_LIST=\
	$(SCRIPTDIR)/mosquitto.sh \
	$(SCRIPTDIR)/mosquitto.conf \
	$(PRIVATEDIR)/configuration.env
MQTT_ARCHIVE_FILE=mosquitto_files.tgz
MQTT_HOST_FOLDER=mosquitto
# build a flat archive with files to transfer
build_mqtt: $(OUTDIR)/$(MQTT_ARCHIVE_FILE)
$(OUTDIR)/$(MQTT_ARCHIVE_FILE): $(MQTT_ARCHIVE_LIST)
	chmod a+x $(SCRIPTDIR)/mosquitto.sh
	$(TAR) -c -v -z -f $@ --transform='s|.*/||' $(MQTT_ARCHIVE_LIST)
deploy_mqtt: $(OUTDIR)/$(MQTT_ARCHIVE_FILE)
	scp $(OUTDIR)/$(MQTT_ARCHIVE_FILE) $(mosquitto_server_address):
	ssh $(mosquitto_server_address) "rm -fr $(MQTT_HOST_FOLDER) && mkdir -p $(MQTT_HOST_FOLDER) && tar --directory=$(MQTT_HOST_FOLDER) -x -v -z -f $(MQTT_ARCHIVE_FILE) && rm -f $(MQTT_ARCHIVE_FILE)"
