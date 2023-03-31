# Makefile

OUTDIR=build
PRIVATEDIR=private
CERTNAME=clientCertificate
CSRFILE=$(OUTDIR)/$(CERTNAME).csr
SSLCONF=$(OUTDIR)/ssl.conf
PRIVKEYFILE=$(OUTDIR)/$(CERTNAME).key
CERTFILEPEM=$(OUTDIR)/$(CERTNAME).crt
CERTFILEP12=$(OUTDIR)/$(CERTNAME).p12

# get specific info from this file
include $(PRIVATEDIR)/config.env

all: $(CERTFILEP12)

init:
	@echo Done.

clean:
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
