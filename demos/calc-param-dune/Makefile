.PHONY: all clean test

DUNE       := jbuilder
EXECUTABLE := calc.exe

all:
	@ if command -v $(DUNE) > /dev/null ; then \
	  $(DUNE) build $(EXECUTABLE) ; \
	else \
	  echo "Error: $(DUNE) is required." ; \
	fi

clean:
	rm -rf `cat .gitignore`
	rm -f *~

test: all
	@echo "The following command should print 42.0:"
	echo "(1 + 2 * 10) * 2" | ./_build/default/$(EXECUTABLE)
