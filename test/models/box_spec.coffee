Box = require '../../app/models/box'
BaseModel = require('action-base').BaseModel
KeyPair = require '../../app/models/key_pair'
BoxUser = require '../../app/models/box_user'

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

  describe '#findUserIds', ->
    box = cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      box = new Box id: 123, owner_id: 42
      sinon.stub BoxUser, 'findMany'

    afterEach ->
      BoxUser.findMany.restore()

    doAction = ->
      box.findUserIds cbSpy

    context 'when there is no error', ->
      context 'when there is a result', ->
        context 'when owner id is included in the result', ->
          beforeEach ->
            BoxUser.findMany.withArgs('box_id = $1', [123], ['user_id'], sinon.match.func).yields null, [
              new BoxUser id: 1, user_id: 42
              new BoxUser id: 2, user_id: 777
              new BoxUser id: 3, user_id: 999
            ]
            doAction()

          it 'invokes callback with no error and ids of users that can access the box, including the owner id', ->
            expect(cbSpy).to.have.been.calledWith sinon.match.falsy, [42, 777, 999]

        context 'when owner id is omitted in the result', ->
          beforeEach ->
            BoxUser.findMany.withArgs('box_id = $1', [123], ['user_id'], sinon.match.func).yields null, [
              new BoxUser id: 1, user_id: 777
              new BoxUser id: 2, user_id: 999
            ]
            doAction()

          it 'invokes callback with no error and ids of users that can access the box, including the owner id', ->
            expect(cbSpy).to.have.been.calledWith sinon.match.falsy, [42, 777, 999]

      context 'when there is no result', ->
        beforeEach ->
          BoxUser.findMany.withArgs('box_id = $1', [123], ['user_id'], sinon.match.func).yields null, []
          doAction()

        it 'invokes callback with no error and with just the owner id', ->
          expect(cbSpy).to.have.been.calledWith sinon.match.falsy, [42]

    context 'when there is an error', ->
      err = new Error

      beforeEach ->
        BoxUser.findMany.withArgs('box_id = $1', [123], ['user_id'], sinon.match.func).yields err
        doAction()

      it 'invokes callback with the error', ->
        expect(cbSpy).to.have.been.calledWith err

  describe '#isAccessibleByUserId', ->
    box = cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      box = new Box id: 1, owner_id: 2

    doAction = (userId) ->
      box.isAccessibleByUserId userId, cbSpy

    context 'when a given user id is the same as the owner_id', ->
      beforeEach ->
        doAction 2

      it 'invokes callback with no error and true', ->
        expect(cbSpy).to.have.been.calledWith sinon.match.falsy, true

    context 'when a given user id is not the same as the owner_id', ->
      context 'when findUserIds calls back with no error', ->
        beforeEach ->
          sinon.stub box, 'findUserIds'
          box.findUserIds.yields null, [2, 3, 4]

        context 'when a given user id is in the list of user ids returned', ->
          beforeEach ->
            doAction 3

          it 'invokes callback with no error and true', ->
            expect(cbSpy).to.have.been.calledWith sinon.match.falsy, true

        context 'when a given user id is not in the list of user ids returned', ->
          beforeEach ->
            doAction 5

          it 'invokes callback with no error and false', ->
            expect(cbSpy).to.have.been.calledWith sinon.match.falsy, false

      context 'when findUserIds calls back with an error', ->
        error = new Error

        beforeEach ->
          sinon.stub box, 'findUserIds'
          box.findUserIds.yields error
          doAction 3

        it 'invokes callback with an error', ->
          expect(cbSpy).to.have.been.calledWith error
