.PHONY: test-chibi test-chicken test-gauche test-gerbil test-kawa test-larceny test-sagittarius test test-all repl clean watch

schemepunk:
	mkdir schemepunk
	for module in $$(find . -name '*.sld'); do\
	  mkdir -p "schemepunk/$$(dirname "$$module")" &&\
	  ln "$$module" "schemepunk/$${module#./}";\
	done
	for module in $$(find ./show -name '*.scm'); do\
	  mkdir -p "schemepunk/$$(dirname "$$module")" &&\
	  ln "$$module" "schemepunk/$${module#./}";\
	done
	ln -s ../polyfills schemepunk/polyfills
	ln -s ../scripts schemepunk/scripts

test-chibi: schemepunk
	./scripts/test-chibi.sh "$$(./scripts/find-tests.sh)"

test-chicken: schemepunk
	./scripts/test-chicken.sh "$$(./scripts/find-tests.sh)"

test-gauche: schemepunk
	./scripts/test-gauche.sh "$$(./scripts/find-tests.sh)"

test-gerbil: schemepunk
	./scripts/test-gerbil.sh "$$(./scripts/find-tests.sh)"

test-kawa: schemepunk
	./scripts/test-kawa.sh "$$(./scripts/find-tests.sh)"

test-larceny: schemepunk
	./scripts/test-larceny.sh "$$(./scripts/find-tests.sh)"

test-sagittarius: schemepunk
	./scripts/test-sagittarius.sh "$$(./scripts/find-tests.sh)"

test: test-gauche

test-all: test-chibi test-gauche test-gerbil test-kawa test-larceny test-chicken test-sagittarius

repl: schemepunk
	rlwrap gosh -r7 -I . -l scripts/repl.scm

clean:
	rm -rf schemepunk
	find . -name '*.c' -delete
	find . -name '*.o' -delete
	find . -name '*.o1' -delete
	find . -name '*.o2' -delete
	find . -name '*.slfasl' -delete
	find . -name '*.so' -delete
	find . -name '*.link' -delete
	find . -name '*.import.scm' -delete
	find . -name '*.build.sh' -delete
	find . -name '*.install.sh' -delete

watch:
	nodemon -e scm,sld --exec 'make test || exit 1'
