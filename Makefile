# Makefile

# configuration is placed here
PRIVATEDIR=private

# generated files are placed here
OUTDIR=generated

CSRFILE=$(OUTDIR)/$(cert_name).csr
SSLCONF=$(OUTDIR)/$(cert_name).conf
PRIVKEYFILE=$(OUTDIR)/$(cert_name).key
CERTFILEPEM=$(OUTDIR)/$(cert_pem)
CERTFILEP12=$(OUTDIR)/$(cert_p12)

# get specific info from this file
include $(OUTDIR)/configuration.mak

all:: $(CERTFILEP12)

init: $(PRIVATEDIR)/configuration.env
	@echo Done.

clean::
	rm -fr $(OUTDIR)

$(PRIVKEYFILE):
	openssl genrsa -out $(PRIVKEYFILE) 4096

$(SSLCONF): ssl.tmpl
	param_fqdn=$(development_address) envsubst < ssl.tmpl > $(SSLCONF)

$(CSRFILE): $(PRIVKEYFILE) $(SSLCONF)
	openssl req -new -sha256 -out $(CSRFILE) -key $(PRIVKEYFILE) -config $(SSLCONF)

$(CERTFILEPEM): $(PRIVKEYFILE) $(CSRFILE)
	openssl x509 -req -sha256 -days 365 -in $(CSRFILE) -signkey $(PRIVKEYFILE) -out $(CERTFILEPEM) -extensions req_ext -extfile $(SSLCONF)

$(CERTFILEP12): $(CERTFILEPEM) $(PRIVKEYFILE)
	openssl pkcs12 -password pass:"$(pkcs12_key)" -export -in $(CERTFILEPEM) -inkey $(PRIVKEYFILE) -out $(CERTFILEP12)

# create config template
template:
	sed -Ee 's/(_key|_address)=.*/\1=_your_value_here_/' < $(PRIVATEDIR)/configuration.env > configuration.tmpl.env

# generate initial empty config from template
$(PRIVATEDIR)/configuration.env:
	mkdir -p $(PRIVATEDIR)
	@if test -e $(PRIVATEDIR)/configuration.env;then echo 'ERROR: conf file already exists: $@';exit 1;fi
	sed 's/=.*/=_fill_here_/' < configuration.tmpl.env > $@
$(OUTDIR)/configuration.mak: $(PRIVATEDIR)/configuration.env
	mkdir -p $(OUTDIR)
	sed 's/{/(/g;s/}/)/g' < $< > $@

# send script to opc simulator
deploy_opcplc:
	ssh $(opcua_server_address) mkdir -p pki/{issuer,trusted}
	scp $(CERTFILEPEM) $(opcua_server_address):pki
	scp start_opc.sh $(opcua_server_address):
	ssh $(opcua_server_address) chmod a+x start_opc.sh

%.pdf: %.md
	pandoc \
		--standalone --from=gfm --to=pdf --pdf-engine=xelatex \
		--resource-path=.. --toc --number-sections \
		--shift-heading-level-by=-1 \
		--variable=include-before:'\newpage' --variable=documentclass:report \
		--variable=date:$$(date '+%Y/%m/%d') --variable=author:'Laurent MARTIN' \
		--variable=mainfont:Arial --variable=urlcolor:blue --variable=geometry:margin=15mm \
		-o $@ $<

doc: README.pdf

clean::
	rm -f README.pdf

# Create a simplified archive
$(OUTDIR)/ACMfg_runtime.tar.gz: $(PRIVATEDIR)/ACMfg_linux_amd64_$(acmfg_version)_developer.tar.gz
	tar zxvf $(PRIVATEDIR)/ACMfg_linux_amd64_$(acmfg_version)_developer.tar.gz ACMfg-$(acmfg_version)/runtime/amd64_linux_2
	rm -fr ACMfg_runtime
	mv ACMfg-$(acmfg_version)/runtime/amd64_linux_2 ACMfg_runtime
	tar -zcvf $@ --no-xattrs ACMfg_runtime
	rm -fr ACMfg-$(acmfg_version) ACMfg_runtime

deploy_ace: $(CERTFILEP12) $(PRIVATEDIR)/configuration.env $(OUTDIR)/ACMfg_runtime.tar.gz
	acmfg_runtime_folder=$(ace_container_work_directory)/ACMfg_runtime envsubst < server.conf.tmpl.yaml > $(OUTDIR)/server.conf.yaml
	scp \
		ace_container_tools.sh \
		deploy_acmfg.sh \
		$(PRIVATEDIR)/configuration.env \
		$(CERTFILEPEM) \
		$(CERTFILEP12) \
		$(OUTDIR)/ACMfg_runtime.tar.gz \
		$(OUTDIR)/server.conf.yaml \
		$(ace_server_address):
