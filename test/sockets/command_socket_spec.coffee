actionBase = require 'action-base'
RainbowSocket = require '../../app/sockets/rainbow_socket'
SocketConnection = actionBase.SocketConnection
SSHHelper = actionBase.SSHHelper
Box = require '../../app/models/box'
KeyPair = require '../../app/models/key_pair'
CommandSocket = require '../../app/sockets/command_socket'
app = require '../../app'

childProcess = require 'child_process'
inherits = require('util').inherits
EventEmitter = require('events').EventEmitter

describe 'CommandSocket', ->
  socket = ws = connection = null

  beforeEach ->
    ws = sinon.stub on: (->), write: (->), close: (->)
    connection = new SocketConnection ws
    connection.userId = 1337
    socket = new CommandSocket connection

  it 'is a subclass of RainbowSocket', ->
    expect(socket).to.be.an.instanceof RainbowSocket

  describe '#lineBuffer', ->
    context 'with empty buffer', ->
      buffer = ''

      beforeEach ->
        buffer = ''

      it 'returns [full line, empty buffer] given newline-terminated data', ->
        [line, buffer] = socket.lineBuffer(":workspace/somefile.txt\n1;2 3:match\n", buffer)
        expect(line).to.eq ":workspace/somefile.txt\n1;2 3:match\n"
        expect(buffer).to.eq ''

      it 'returns [line up to last newline, remainder] when data is not newline-terminated', ->
        [line, buffer] = socket.lineBuffer("somefile.txt\n1;2 3: match\n2;3 4:", buffer)
        expect(line).to.eq "somefile.txt\n1;2 3: match\n"
        expect(buffer).to.eq '2;3 4:'

      it 'returns [empty, entire line] given line with no newlines', ->
        [line, buffer] = socket.lineBuffer("somefile.txt", buffer)
        expect(line).to.eq ''
        expect(buffer).to.eq 'somefile.txt'

    context 'with existing buffer', ->
      buffer = ''

      beforeEach ->
        buffer = '<existing>'

      it 'returns [buffer+full line, empty buffer] given newline-terminated data', ->
        [line, buffer] = socket.lineBuffer(":workspace/somefile.txt\n1;2 3:match\n", buffer)
        expect(line).to.eq "<existing>:workspace/somefile.txt\n1;2 3:match\n"
        expect(buffer).to.eq ''

      it 'returns [buffer+line up to last newline, remainder] when data is not newline-terminated', ->
        [line, buffer] = socket.lineBuffer("somefile.txt\n1;2 3: match\n2;3 4:", buffer)
        expect(line).to.eq '<existing>somefile.txt\n1;2 3: match\n'
        expect(buffer).to.eq '2;3 4:'

      it 'returns [empty, buffer + new data] given line with no newlines', ->
        [line, buffer] = socket.lineBuffer("somefile.txt", buffer)
        expect(line).to.eq ''
        expect(buffer).to.eq '<existing>somefile.txt'

  describe '#shellEscape', ->
    it 'removes newlines', ->
      expect(socket.shellEscape("new\nline")).to.eql 'new\\\\nline'

    it 'escapes backticks', ->
      expect(socket.shellEscape("evil`rm -rf`")).to.eql 'evil\\`rm\\ -rf\\`'

    it 'escapes $(command)', ->
      expect(socket.shellEscape("evil$(rm -rf)")).to.eql 'evil\\$\\(rm\\ -rf\\)'

    it 'escapes backslashes for regex searches', ->
      expect(socket.shellEscape("regex search\\w\\w")).to.eql 'regex\\ search\\\\w\\\\w'

    it 'escapes semicolons', ->
      expect(socket.shellEscape("test; rm -rf")).to.eql 'test\\;\\ rm\\ -rf'

    it 'does not escape wildcards', ->
      expect(socket.shellEscape('*.p?')).to.eql '*.p?'
