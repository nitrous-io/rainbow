BaseCommand = require '../../app/commands/search_command'

describe 'BaseCommand', ->
  command = sendSpy = null

  beforeEach ->
    sendSpy = sinon.spy()
    command = new BaseCommand 'term', 'location', 'options', sendSpy
    sinon.stub(command, 'commandPath').returns('/usr/bin/yes')
    sinon.stub(command, 'commandArguments').returns([])

  describe 'stdoutFn', ->
    it 'sends newline-terminated data back', ->
      command.stdoutFn(':workspace/README.md\n')
      expect(sendSpy).to.be.calledWith('commandOutput', ':workspace/README.md\n')

    context 'when lines exceed limit', ->
      beforeEach ->
        sinon.stub(command, '_limitLines').returns(['', -1])

      it 'sends limit error', ->
        command.stdoutFn(':workspace/README.md\n', kill: -> {})
        expect(sendSpy).to.be.calledWith('commandError', command.errorSlugs.limit)

      it 'kills child process', ->
        cprocess = kill: -> {}
        killSpy = sinon.spy(cprocess, 'kill')
        command.stdoutFn(':workspace/README.md\n', cprocess)
        expect(killSpy).to.be.calledWith()

  describe 'stderrFn', ->
    it 'appends to errBuffer', ->
      expect(command.errBuffer).to.eql ''
      command.stderrFn("Invalid path\n", {})
      expect(command.errBuffer).to.eql 'Invalid path\n'
      command.stderrFn("Malformed arguments\n", {})
      expect(command.errBuffer).to.eql 'Invalid path\nMalformed arguments\n'

  describe 'closeFn', ->
    handlerSpy = null

    beforeEach ->
      handlerSpy = sinon.spy(command, '_handleErrors')

    it 'calls _handleErrors with errBuffer', ->
      command.errBuffer = "Error stat()ing"
      command.closeFn(0)
      expect(handlerSpy).to.be.calledWith('Error stat()ing')

    it 'calls _handleErrors with multiple errBuffer lines', ->
      sinon.stub(command, 'detectErrors').returns('errslug')
      command.errBuffer = "Bad\nWrong\nMistake"
      command.closeFn(0)
      expect(handlerSpy).to.be.calledWith('Bad')
      expect(handlerSpy).to.be.calledWith('Wrong')
      expect(handlerSpy).to.be.calledWith('Mistake')

    it 'does not call _handleErrors on empty errBuffer', ->
      command.errBuffer = ''
      command.closeFn(0)
      expect(handlerSpy).not.to.be.called

    it 'sends commandComplete', ->
      command.closeFn(0)
      expect(sendSpy).to.be.calledWith('commandComplete', 0)

  describe '#_lineBuffer', ->
    context 'with empty buffer', ->
      buffer = ''

      beforeEach ->
        buffer = ''

      it 'returns [full line, empty buffer] given newline-terminated data', ->
        [line, buffer] = command._lineBuffer(":workspace/somefile.txt\n1;2 3:match\n", buffer)
        expect(line).to.eq ":workspace/somefile.txt\n1;2 3:match\n"
        expect(buffer).to.eq ''

      it 'returns [line up to last newline, remainder] when data is not newline-terminated', ->
        [line, buffer] = command._lineBuffer("somefile.txt\n1;2 3: match\n2;3 4:", buffer)
        expect(line).to.eq "somefile.txt\n1;2 3: match\n"
        expect(buffer).to.eq '2;3 4:'

      it 'returns [empty, entire line] given line with no newlines', ->
        [line, buffer] = command._lineBuffer("somefile.txt", buffer)
        expect(line).to.eq ''
        expect(buffer).to.eq 'somefile.txt'

    context 'with existing buffer', ->
      buffer = ''

      beforeEach ->
        buffer = '<existing>'

      it 'returns [buffer+full line, empty buffer] given newline-terminated data', ->
        [line, buffer] = command._lineBuffer(":workspace/somefile.txt\n1;2 3:match\n", buffer)
        expect(line).to.eq "<existing>:workspace/somefile.txt\n1;2 3:match\n"
        expect(buffer).to.eq ''

      it 'returns [buffer+line up to last newline, remainder] when data is not newline-terminated', ->
        [line, buffer] = command._lineBuffer("somefile.txt\n1;2 3: match\n2;3 4:", buffer)
        expect(line).to.eq '<existing>somefile.txt\n1;2 3: match\n'
        expect(buffer).to.eq '2;3 4:'

      it 'returns [empty, buffer + new data] given line with no newlines', ->
        [line, buffer] = command._lineBuffer("somefile.txt", buffer)
        expect(line).to.eq ''
        expect(buffer).to.eq '<existing>somefile.txt'

  describe '#_shellEscape', ->
    it 'removes newlines', ->
      expect(command._shellEscape("new\nline")).to.eql 'new\\\\nline'

    it 'escapes backticks', ->
      expect(command._shellEscape("evil`rm -rf`")).to.eql 'evil\\`rm\\ -rf\\`'

    it 'escapes $(command)', ->
      expect(command._shellEscape("evil$(rm -rf)")).to.eql 'evil\\$\\(rm\\ -rf\\)'

    it 'escapes backslashes for regex searches', ->
      expect(command._shellEscape("regex search\\w\\w")).to.eql 'regex\\ search\\\\w\\\\w'

    it 'escapes semicolons', ->
      expect(command._shellEscape("test; rm -rf")).to.eql 'test\\;\\ rm\\ -rf'

    it 'does not escape wildcards', ->
      expect(command._shellEscape('*.p?')).to.eql '*.p?'

  describe '#_limitLines', ->
    beforeEach ->
      command.resultLimit = 3

    it 'with no newlines', ->
      [data, newCount] = command._limitLines "line 1", 0
      expect(data).to.eql 'line 1'
      expect(newCount).to.eql 0

    it 'with lines within limit', ->
      [data, newCount] = command._limitLines "line 1\n", 1
      expect(data).to.eql 'line 1\n'
      expect(newCount).to.eql 2

      [data, newCount] = command._limitLines "line 1\nline 2\n", 1
      expect(data).to.eql 'line 1\nline 2\n'
      expect(newCount).to.eql 3

    it 'with lines exceeding limit', ->
      [data, newCount] = command._limitLines 'line 1\nline 2\nline 3\nline 4\n', 0
      expect(data).to.eql 'line 1\nline 2\nline 3\n'
      expect(newCount).to.eql -1

    it 'with line count exactly at threshold', ->
      [data, newCount] = command._limitLines("line 1\n", 3)
      expect(data).to.eql ''
      expect(newCount).to.eql -1

  describe '#_handleErrors', ->
    cb = logger = null

    beforeEach ->
      cb = sinon.spy()
      logger = sinon.stub(console, 'log')

    afterEach ->
      console.log.restore()

    it 'runs callback on handled error', ->
      sinon.stub(command, 'detectErrors').returns('OHNOES')
      command._handleErrors('some error', cb)
      expect(logger).not.to.have.been.called
      expect(cb).to.have.been.calledWith('OHNOES')

    it 'logs on unhandled error', ->
      sampleErr = "ERR: Never happens\n"
      command._handleErrors(sampleErr, cb)
      expect(logger).to.have.been.calledWithMatch(/Never happens/)
      expect(cb).not.to.have.been.called

    it 'logs single line on unhandled error', ->
      sampleErr = "ERR: Spans\nmultiple\nlines\n"
      command._handleErrors(sampleErr, cb)
      expect(logger).to.have.been.calledWith('Unhandled /usr/bin/yes error: ERR: Spans\\nmultiple\\nlines\\n')
      expect(cb).not.to.have.been.called
