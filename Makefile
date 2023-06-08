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
	cp configuration.tmpl.env $@

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
# Deployments

# build files to send to opc simulator
build_opcplc: $(OUTDIR)/opc_server_files.tgz

# GNU tar required here
$(OUTDIR)/opc_server_files.tgz: $(OUTDIR)/$(cert_pem)
	chmod a+x $(SCRIPTDIR)/create_container_opcplc.sh
	$(TAR) -c -v -z -f $@ \
	  --transform='s|.*/||' \
	  $(SCRIPTDIR)/create_container_opcplc.sh \
	  $(PRIVATEDIR)/configuration.env \
	  $(OUTDIR)/$(cert_pem)
# send files to simulator host
deploy_opcplc: $(OUTDIR)/opc_server_files.tgz
	scp $(OUTDIR)/opc_server_files.tgz $(opcua_server_address):
	ssh $(opcua_server_address) 'rm -fr opc_files && mkdir -p opc_files && tar --directory=opc_files -x -v -z -f opc_server_files.tgz && rm -f opc_server_files.tgz'
ssh_opcplc:
	ssh $(opcua_server_address)

# generate files to integration server host
build_ace: $(OUTDIR)/ace_server_files.tgz
# byuild a flat archive with files to transfer
$(OUTDIR)/ace_server_files.tgz: $(OUTDIR)/$(cert_p12) $(PRIVATEDIR)/configuration.env $(PRIVATEDIR)/$(acmfg_tar) $(SCRIPTDIR)/server.conf.tmpl.yaml
	$(TAR) -c -v -z -f $@ \
	  --transform='s|.*/||' \
	  $(SCRIPTDIR)/ace_container_tools.rc.sh \
	  $(SCRIPTDIR)/deploy_acmfg.sh \
	  $(SCRIPTDIR)/server.conf.tmpl.yaml \
	  $(PRIVATEDIR)/configuration.env \
	  $(PRIVATEDIR)/$(acmfg_tar) \
	  $(OUTDIR)/$(cert_pem) \
	  $(OUTDIR)/$(cert_p12)
# send files to ace host
deploy_ace: $(OUTDIR)/ace_server_files.tgz
	scp $(OUTDIR)/ace_server_files.tgz \
	  $(ace_server_address):
	ssh $(ace_server_address) 'rm -fr ace_files && mkdir -p ace_files && tar --directory=ace_files -x -v -z -f ace_server_files.tgz && rm -f ace_server_files.tgz'
ssh_ace:
	ssh $(ace_server_address)
