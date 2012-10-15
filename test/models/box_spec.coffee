Box = require '../../app/models/box'
BaseModel = require('action-base').BaseModel
KeyPair = require '../../app/models/key_pair'

describe 'Box', ->
  it 'is a subclass of BaseModel', ->
    expect(new Box).to.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    expect(Box.tableName).to.equal 'boxes'

  describe '#findKeyPair', ->
    box = cbSpy = null

    beforeEach ->
      box = new Box(id: 123)
      sinon.stub KeyPair, 'findOne'
      cbSpy = sinon.spy()

    afterEach ->
      KeyPair.findOne.restore()

    it 'finds a key pair object for this box', ->
      box.findKeyPair(cbSpy)
      expect(KeyPair.findOne).to.have.been.calledWith 'box_id = $1', [123], cbSpy

