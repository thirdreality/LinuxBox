TARGET = tcpserver
SRCS := crypto_helper.c tcpserver.cpp

LDFLAGS += -lcrypto

all:
	$(CXX) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $(TARGET) -lssl -lcrypto

clean:
	rm $(TARGET)
