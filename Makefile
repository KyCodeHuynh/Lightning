# Based on example Makefile:
# https://www.cs.swarthmore.edu/~newhall/unixhelp/howto_makefiles.html
MAKEOPTS = "-j 2"

CXX = g++
SRC_FLAGS = -std=c++0x -I nginx-configparser/ -Wall -Wextra
LDFLAGS = -lpthread -lboost_filesystem -lboost_system -lboost_thread -lboost_regex

PARSER_PATH = ./nginx-configparser/
MD_PATH = ./cpp-markdown/
GTEST_DIR = nginx-configparser/googletest/googletest
GTEST_FLAGS = -isystem ${GTEST_DIR}/include
TEST_COV = --coverage # --coverage is a synonym for-fprofile-arcs, -ftest-coverage(compiling) and-lgcov(linking).

# TODO: Split out dependency handling so that we can avoid rebuilding
.PHONY: $(TARGET) $(TESTS) all test integration_test clean

TARGET = lightning
TESTS = server_config_test
SRC = $(PARSER_PATH)config_parser.cc lightning_main.cc \
	  lightning_server.cc server_config.cc mime_types.cc \
	  request_handlers.cc request_router.cc request.cc response.cc \
	  server_stats.cc $(MD_PATH)markdown.cpp \
	  $(MD_PATH)markdown-tokens.cpp

all: $(TARGET)

test: LDFLAGS += $(TEST_COV)
test: integration_test

# Build Lightning binary
build: Dockerfile
	# Create image for compiling Lightning under Ubuntu 14.04/Trusty
	docker build -t lightning.build .
	# Output tarballed Lightning binary
	docker run --rm lightning.build > lightning.tar

# Deploy Lightning binary
deploy: Dockerfile.run lightning.tar
	# Copy over binary + config + test files
	rm -rf deploy/
	mkdir deploy/
	cp lightning.tar deploy/
	cp -r simple_config test/ deploy/
	# Create image for running Lightning under BusyBox
	cd deploy/
	docker build -f Dockerfile.run -t lightning.deploy .
	# Run Lightning!
	docker run --rm -t -p 2020:2020 lightning.deploy


$(TARGET): $(SRC)
	$(CXX) $(SRC_FLAGS) $(SRC) $(LDFLAGS) -o $(TARGET)

# TODO: Generalize for multiple unit tests
# TODO: These assume compilation on LINUX, so we need to add an OS check
$(TESTS):
	# Build and link GTest
	$(CXX) $(SRC_FLAGS) $(GTEST_FLAGS) -I${GTEST_DIR} -c ${GTEST_DIR}/src/gtest-all.cc
	ar -rv libgtest.a gtest-all.o
	# Build our own tests, using GTest
	# TODO: Figure out how to name multiple CC and produce corresponding object for each
	$(CXX) $(SRC_FLAGS) $(GTEST_FLAGS) $(PARSER_PATH)config_parser.cc server_config.cc $(TESTS).cc \
		${GTEST_DIR}/src/gtest_main.cc libgtest.a $(LDFLAGS) -o $(TESTS)

	$(CXX) $(SRC_FLAGS) $(GTEST_FLAGS) $(PARSER_PATH)config_parser.cc mime_types.cc server_config.cc \
		request_router.cc request.cc response.cc request_handlers.cc request_handlers_test.cc \
		server_stats.cc ${GTEST_DIR}/src/gtest_main.cc libgtest.a $(MD_PATH)markdown.cpp \
		$(MD_PATH)markdown-tokens.cpp $(LDFLAGS) -o request_handlers_test

integration_test: $(TARGET) $(TESTS)
	./$(TESTS)
	./request_handlers_test
	./$(TARGET) simple_config &
	lcov -t "Lightning Coverage" -o test_coverage.info -c -d .
	genhtml -o test_coverage test_coverage.info
	python3 lightning_integration_test.py
	pkill $(TARGET)

clean:
	$(RM) $(TARGET) $(TESTS) *.o *.a *.gcov *.gcno *.gcda -r test_coverage* request_handlers_test $(TARGET).tar*
