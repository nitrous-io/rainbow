BoxAdmin = require '../../app/models/box_admin'

describe 'BoxAdmin', ->
  it 'has correct table name', ->
    expect(BoxAdmin.tableName).to.eq 'box_admins'

  describe '#isAllowed', ->
    cbSpy = null
    beforeEach ->
      sinon.spy BoxAdmin, "findOne"
      cbSpy = sinon.spy()

    afterEach -> BoxAdmin.findOne.restore()

    it 'is true when user is in the list of box admin', ->
      BoxAdmin.isAllowed 123, 456, cbSpy
      expect(BoxAdmin.findOne).to.be.calledWith 'box_id = $1 AND user_id = $2', [123, 456], ['count(*)'], sinon.match.func
      BoxAdmin.findOne.callArgWith 3, null,  { rows: { count: 1 } }
      expect(cbSpy).to.be.calledWith null, true

    it 'is false when user is not in the list of box admin', ->
      BoxAdmin.isAllowed 123, 456, cbSpy
      BoxAdmin.findOne.callArgWith 3, null,  { rows: { count: 0 } }
      expect(cbSpy).to.be.calledWith "not allowed to access this box", false

    it 'is false when the query returns errors', ->
      BoxAdmin.isAllowed 123, 456, cbSpy
      BoxAdmin.findOne.callArgWith 3, "OMG", null
      expect(cbSpy).to.be.calledWith "OMG", false
