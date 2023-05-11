# Makefile

# configuration is placed here
PRIVATEDIR=private

# generated files are placed here
OUTDIR=generated

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
	sed -Ee 's/(_key|_address)=.*/\1=_your_value_here_/' < $(PRIVATEDIR)/configuration.env > configuration.tmpl.env

clean::
	rm -fr $(OUTDIR)


###################################
# Client certificate
CSRFILE=$(OUTDIR)/$(cert_name).csr
SSLCONF=$(OUTDIR)/$(cert_name).conf
PRIVKEYFILE=$(OUTDIR)/$(cert_name).key
CERTFILEPEM=$(OUTDIR)/$(cert_pem)
CERTFILEP12=$(OUTDIR)/$(cert_p12)

all:: $(CERTFILEP12)

$(PRIVKEYFILE):
	openssl genrsa -out $(PRIVKEYFILE) 4096

$(SSLCONF): ssl.tmpl
	param_fqdn=$(cert_address) envsubst < ssl.tmpl > $(SSLCONF)

$(CSRFILE): $(PRIVKEYFILE) $(SSLCONF)
	openssl req -new -sha256 -out $(CSRFILE) -key $(PRIVKEYFILE) -config $(SSLCONF)

$(CERTFILEPEM): $(PRIVKEYFILE) $(CSRFILE)
	openssl x509 -req -sha256 -days 365 -in $(CSRFILE) -signkey $(PRIVKEYFILE) -out $(CERTFILEPEM) -extensions req_ext -extfile $(SSLCONF)

$(CERTFILEP12): $(CERTFILEPEM) $(PRIVKEYFILE)
	openssl pkcs12 -password pass:"$(cert_pkcs12_password)" -export -in $(CERTFILEPEM) -inkey $(PRIVKEYFILE) -out $(CERTFILEP12)

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

clean::
	rm -f README.pdf

###################################
# Deployments

# build files to send to opc simulator
build_opcplc: $(OUTDIR)/opc_server_files.tgz

# GNU tar required here
$(OUTDIR)/opc_server_files.tgz: $(CERTFILEPEM)
	chmod a+x create_container_opcplc.sh
	$(TAR) -c -v -z -f $@ \
	  --transform='s|.*/||' \
	  create_container_opcplc.sh \
	  $(PRIVATEDIR)/configuration.env \
	  $(CERTFILEPEM)
# send files to simulator host
deploy_opcplc: $(OUTDIR)/opc_server_files.tgz
	scp $(OUTDIR)/opc_server_files.tgz $(opcua_server_address):
	ssh $(opcua_server_address) tar zxvf opc_server_files.tgz

# generate files to integration server host
build_ace: $(OUTDIR)/ace_server_files.tgz

$(OUTDIR)/ace_server_files.tgz: $(CERTFILEP12) $(PRIVATEDIR)/configuration.env $(PRIVATEDIR)/$(acmfg_tar) server.conf.tmpl.yaml
	$(TAR) -c -v -z -f $@ \
	  --transform='s|.*/||' \
	  ace_container_tools.rc.sh \
	  deploy_acmfg.sh \
	  server.conf.tmpl.yaml \
	  $(PRIVATEDIR)/configuration.env \
	  $(PRIVATEDIR)/$(acmfg_tar) \
	  $(CERTFILEPEM) \
	  $(CERTFILEP12)
# send files to ace host
deploy_ace: $(OUTDIR)/ace_server_files.tgz
	scp $(OUTDIR)/ace_server_files.tgz \
	  $(ace_server_address):
	ssh $(opcua_server_address) tar zxvf ace_server_files.tgz
