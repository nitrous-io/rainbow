Box       = require '../../app/models/box'
BaseModel = require('action-base').BaseModel
BoxAdmin  = require '../../app/models/box_admin'
KeyPair   = require '../../app/models/key_pair'
_         = require 'underscore'

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

  describe '#forUser', ->
    cbSpy = null
    boxId = 123
    userId = 234

    beforeEach ->
      sinon.stub Box, 'findOne'
      sinon.stub BoxAdmin, 'isAllowed'
      cbSpy = sinon.spy()

    afterEach ->
      Box.findOne.restore()
      BoxAdmin.isAllowed.restore()

    it 'determines if user is collaborator of the box', (done) ->
      Box.forUser boxId, userId, cbSpy
      asyncDone done, ->
	expect(BoxAdmin.isAllowed).to.be.calledWith 123, 234, sinon.match.any

    context 'when user is collaborator of the box', ->
      beforeEach (done) ->
	Box.forUser boxId, userId, cbSpy
	asyncDone done, ->
	  expect(BoxAdmin.isAllowed).to.be.called
	  BoxAdmin.isAllowed.callArgWith 2, null, true

      it 'tries to get the box out', (done) ->
	asyncDone done, ->
	  expect(Box.findOne).to.be.calledWith "id = $1", [234], 'id, owner_id, host, port', sinon.match.any

      it 'returns the box when it exists', (done) ->
	boxAttr = {id: boxId, owner_id: userId, host: "127.0.0.1", port: "9999" }
	asyncDone done, ->
	  Box.findOne.callArgWith 3, null, new Box(boxAttr)
	  expect(cbSpy).to.be.calledWith(null, sinon.match(boxAttr))

      it 'returns nothing when the box does not exists', (done) ->
	Box.forUser boxId, userId, cbSpy
	asyncDone done, ->
	  Box.findOne.callArgWith 3, null, null
	  expect(cbSpy).to.be.calledWith("box not found")

    it 'returns nothing when user is not collaborator of the box', (done) ->
      Box.forUser boxId, userId, cbSpy
      asyncDone done, ->
	BoxAdmin.isAllowed.callArgWith 2, "not allowed", false
	expect(cbSpy).to.be.calledWith "not allowed"
