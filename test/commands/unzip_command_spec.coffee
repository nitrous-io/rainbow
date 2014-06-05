UnzipCommand = require '../../app/commands/unzip_command'

describe 'UnzipCommand', ->
  command = sendSpy = null

  beforeEach ->
    sendSpy = sinon.spy()
    command = new UnzipCommand 'some/path/project.zip', sendSpy

  describe '#extractDir', ->
    it 'will be the file path without the extension', ->
      command.file = '/home/action/some/path/project.zip'
      expect(command.extractDir()).to.eql '/home/action/some/path/project'

      command.file = '/home/action/some/path/project.ZIP'
      expect(command.extractDir()).to.eql '/home/action/some/path/project'

      command.file = '/home/action/some/path.zip/project.zip'
      expect(command.extractDir()).to.eql '/home/action/some/path.zip/project'

  describe '#commandArguments', ->
    args = null

    beforeEach ->
      args = command.commandArguments()

    it 'sets modifiers for unzip command', ->
      expect(args).to.contain '-n'
      expect(args).to.contain '-q'

    it 'has the file path and directory to extract', ->
      expect(args.slice(-2)).to.deep.equal ['/home/action/some/path/project.zip', '-d /home/action/some/path/project']

  describe '#detectErrors', ->
    it 'detects file not found error', ->
      sampleErr = "/usr/bin/unzip:  cannot find or open archive.zip\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.fileNotFound

    it 'detects extract directory needed error', ->
      sampleErr = "error:  must specify directory to which to extract with -d option\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.extractDirNeeded

    it 'detects cannot create extract directory error', ->
      sampleErr = "error: checkdir:  cannot create extraction directory: /home/some/path\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.cannotCreateDir
