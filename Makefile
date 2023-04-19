# Makefile

# configuration is placed here
PRIVATEDIR=private

# generated files are placed here
OUTDIR=build

CERTNAME=clientCertificate
CSRFILE=$(OUTDIR)/$(CERTNAME).csr
SSLCONF=$(OUTDIR)/$(CERTNAME).conf
PRIVKEYFILE=$(OUTDIR)/$(CERTNAME).key
CERTFILEPEM=$(OUTDIR)/$(CERTNAME).crt
CERTFILEP12=$(OUTDIR)/$(CERTNAME).p12

# get specific info from this file
include $(PRIVATEDIR)/config.env

all:: $(CERTFILEP12)

doc: README.pdf

init:
	@echo Done.

clean::
	rm -fr $(OUTDIR)

$(PRIVKEYFILE):
	mkdir -p $(OUTDIR)
	openssl genrsa -out $(PRIVKEYFILE) 4096

$(SSLCONF): ssl.tmpl
	param_fqdn=$(CLIENT_ADDRESS) envsubst < ssl.tmpl > $(SSLCONF)

$(CSRFILE): $(PRIVKEYFILE) $(SSLCONF)
	openssl req -new -sha256 -out $(CSRFILE) -key $(PRIVKEYFILE) -config $(SSLCONF)

$(CERTFILEPEM): $(PRIVKEYFILE) $(CSRFILE)
	openssl x509 -req -sha256 -days 365 -in $(CSRFILE) -signkey $(PRIVKEYFILE) -out $(CERTFILEPEM) -extensions req_ext -extfile $(SSLCONF)

$(CERTFILEP12): $(CERTFILEPEM) $(PRIVKEYFILE)
	openssl pkcs12 -password pass:"$(PASSPHRASE)" -export -in $(CERTFILEPEM) -inkey $(PRIVKEYFILE) -out $(CERTFILEP12)

# create config template
template:
	sed 's/=.*/=_your_value_here_/' < $(PRIVATEDIR)/config.env > config.tmpl
	sed 's/_key=.*/_key=_your_value_here_/' < $(PRIVATEDIR)/ace_container_config.sh > ace_container_config.tmpl.sh

# generate initial empty config from template
$(PRIVATEDIR)/config.env:
	mkdir -p $(PRIVATEDIR)
	test ! -e $(PRIVATEDIR)/config.env
	sed 's/=.*/=_fill_here_/' < config.tmpl > $(PRIVATEDIR)/config.env

# send script to opc simulator
deploy:
	ssh $(SERVER_ADDRESS) mkdir -p pki/{issuer,trusted}
	scp $(CERTFILEPEM) $(SERVER_ADDRESS):pki
	scp start_opc.sh $(SERVER_ADDRESS):
	ssh $(SERVER_ADDRESS) chmod a+x start_opc.sh

%.pdf: %.md
	pandoc \
		--standalone --from=gfm --to=pdf --pdf-engine=xelatex \
		--resource-path=.. --toc --number-sections \
		--shift-heading-level-by=-1 \
		--variable=include-before:'\newpage' --variable=documentclass:report \
		--variable=date:$$(date '+%Y/%m/%d') --variable=author:'Laurent MARTIN' \
		--variable=mainfont:Arial --variable=urlcolor:blue --variable=geometry:margin=15mm \
		-o $@ $<

clean::
	rm -f README.pdf

$(PRIVATEDIR)/ace_container_config.sh:
	mkdir -p $(PRIVATEDIR)
	@if test -e $(PRIVATEDIR)/ace_container_config.sh;then echo 'ERROR: conf file already exists: $@';exit 1;fi
	sed 's/=.*/=_fill_here_/' < ace_container_config.tmpl.sh > $@

conf_ace: $(PRIVATEDIR)/ace_container_config.sh

deploy_ace: $(PRIVATEDIR)/ace_container_config.sh
	scp $(PRIVATEDIR)/ace_container_config.sh ace_container_tools.sh $(SERVER_ADDRESS):
