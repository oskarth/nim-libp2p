import unittest
import chronos
import ../libp2p/[connection,
                  transports/transport,
                  transports/tcptransport,
                  multiaddress,
                  wire]

when defined(nimHasUsed): {.used.}

suite "TCP transport":
  test "test listener: handle write":
    proc testListener(): Future[bool] {.async, gcsafe.} =
      let ma: MultiAddress = Multiaddress.init("/ip4/0.0.0.0/tcp/0")
      proc connHandler(conn: Connection): Future[void] {.async, gcsafe.} =
        result = conn.write(cstring("Hello!"), 6)

      let transport: TcpTransport = newTransport(TcpTransport)
      asyncCheck await transport.listen(ma, connHandler)
      let streamTransport: StreamTransport = await connect(transport.ma)
      let msg = await streamTransport.read(6)
      await transport.close()
      await streamTransport.closeWait()

      result = cast[string](msg) == "Hello!"

    check:
      waitFor(testListener()) == true

  test "test listener: handle read":
    proc testListener(): Future[bool] {.async.} =
      let ma: MultiAddress = Multiaddress.init("/ip4/0.0.0.0/tcp/0")
      proc connHandler(conn: Connection): Future[void] {.async, gcsafe.} =
        let msg = await conn.read(6)
        check cast[string](msg) == "Hello!"

      let transport: TcpTransport = newTransport(TcpTransport)
      asyncCheck await transport.listen(ma, connHandler)
      let streamTransport: StreamTransport = await connect(transport.ma)
      let sent = await streamTransport.write("Hello!", 6)
      result = sent == 6

    check:
      waitFor(testListener()) == true

  test "test dialer: handle write":
    proc testDialer(address: TransportAddress): Future[bool] {.async.} =
      proc serveClient(server: StreamServer,
                       transp: StreamTransport) {.async, gcsafe.} =
        var wstream = newAsyncStreamWriter(transp)
        await wstream.write("Hello!")
        await wstream.finish()
        await wstream.closeWait()
        await transp.closeWait()
        server.stop()
        server.close()

      var server = createStreamServer(address, serveClient, {ReuseAddr})
      server.start()

      let ma: MultiAddress = MultiAddress.init(server.sock.getLocalAddress())
      let transport: TcpTransport = newTransport(TcpTransport)
      let conn = await transport.dial(ma)
      let msg = await conn.read(6)
      result = cast[string](msg) == "Hello!"

      server.stop()
      server.close()
      await server.join()
    check waitFor(testDialer(initTAddress("0.0.0.0:0"))) == true

  test "test dialer: handle write":
    proc testDialer(address: TransportAddress): Future[bool] {.async, gcsafe.} =
      proc serveClient(server: StreamServer,
                        transp: StreamTransport) {.async, gcsafe.} =
        var rstream = newAsyncStreamReader(transp)
        let msg = await rstream.read(6)
        check cast[string](msg) == "Hello!"

        await rstream.closeWait()
        await transp.closeWait()
        server.stop()
        server.close()

      var server = createStreamServer(address, serveClient, {ReuseAddr})
      server.start()

      let ma: MultiAddress = MultiAddress.init(server.sock.getLocalAddress())
      let transport: TcpTransport = newTransport(TcpTransport)
      let conn = await transport.dial(ma)
      await conn.write(cstring("Hello!"), 6)
      result = true

      server.stop()
      server.close()
      await server.join()
    check waitFor(testDialer(initTAddress("0.0.0.0:0"))) == true

  test "e2e: handle write":
    proc testListenerDialer(): Future[bool] {.async.} =
      let ma: MultiAddress = Multiaddress.init("/ip4/0.0.0.0/tcp/0")
      proc connHandler(conn: Connection): Future[void] {.async, gcsafe.} =
        result = conn.write(cstring("Hello!"), 6)

      let transport1: TcpTransport = newTransport(TcpTransport)
      asyncCheck await transport1.listen(ma, connHandler)

      let transport2: TcpTransport = newTransport(TcpTransport)
      let conn = await transport2.dial(transport1.ma)
      let msg = await conn.read(6)
      await transport1.close()

      result = cast[string](msg) == "Hello!"

    check:
      waitFor(testListenerDialer()) == true

  test "e2e: handle read":
    proc testListenerDialer(): Future[bool] {.async.} =
      let ma: MultiAddress = Multiaddress.init("/ip4/0.0.0.0/tcp/0")
      proc connHandler(conn: Connection): Future[void] {.async, gcsafe.} =
        let msg = await conn.read(6)
        check cast[string](msg) == "Hello!"

      let transport1: TcpTransport = newTransport(TcpTransport)
      asyncCheck await transport1.listen(ma, connHandler)

      let transport2: TcpTransport = newTransport(TcpTransport)
      let conn = await transport2.dial(transport1.ma)
      await conn.write(cstring("Hello!"), 6)
      await transport1.close()
      result = true

    check:
      waitFor(testListenerDialer()) == true
