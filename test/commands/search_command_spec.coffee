SearchCommand = require '../../app/commands/search_command'

describe 'SearchCommand', ->
  command = sendSpy = null

  beforeEach ->
    sendSpy = sinon.spy()
    command = new SearchCommand 'term', 'location', 'options', sendSpy

  describe '#commandArguments', ->
    args = null

    beforeEach ->
      args = command.commandArguments()

    it 'has defaults for ag', ->
      expect(args).to.contain '--ackmate'
      expect(args).to.contain '--group'
      expect(args).to.contain '--all-text'

    it 'has term and location', ->
      expect(args.slice(-2)).to.deep.equal ['term', 'location']

  describe '#_optionArguments', ->
    it 'detects multiple options', ->
      command.options = 'ignoreCase,literal'
      expect(command._optionArguments()).to.eql ['--ignore-case', '--literal']

    it 'detects literal option', ->
      command.options = 'literal'
      expect(command._optionArguments()).to.eql ['--literal']

    it 'detects ignore-case option', ->
      command.options = 'ignoreCase'
      expect(command._optionArguments()).to.eql ['--ignore-case']

    it 'ignores unsupported options', ->
      command.options = 'removeAllFiles,destroyBox,literal'
      expect(command._optionArguments()).to.eql ['--literal']

    it 'removes ignore-case option if term has multibyte characters', ->
      command.term = 'ファイル'
      command.options = 'ignoreCase'
      expect(command._optionArguments()).to.eql []

  describe '#detectErrors', ->
    it 'detects path not found error', ->
      sampleErr = "ERR: Error stat()ing: werkspice\nERR: Error opening directory werkspice: No such file or directory\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.pathNotFound

    it 'detects bad regex error', ->
      sampleErr = "ERR:  pcre_compile failed at position 4. Error: missing )\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.badRegex
