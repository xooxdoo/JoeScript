###

## On Interpretation ##

JObject is the base runtime object class.

The __xyz__ methods are methods meant to be called in a runtime context (with a thread).
(except some like __str__, where the thread ($) may be optional)
Some methods like __get__ can pause the thread. The value is available in @last when
the thread is resumed. This means the bitcode instruction wants to return obj.__get__(...),
which preserves the behavior of returning a value. However, these methods will return null
when pausing the thread, so you could alternatively check for that.

  if value=obj.__get__($, key) is null
    # do something else
  else i9n.value = value
  # continue bitcode instruction

Sometimes it is necessary to perform actions after a method call, though the
instruction doesn't depend on the result of these actions. In this case the JObject::emit
mechanism is suitable. Just add a handler to the object via JObject::addHandler and listen.
TODO mechanism to remove a listener...

###

log = no

{ clazz,
  colors:{red, blue, cyan, magenta, green, normal, black, white, yellow}
  collections:{Set}} = require('cardamom')
{inspect} = require 'util'
assert = require 'assert'
{debug, info, warn, fatal} = require('nogg').logger __filename.split('/').last()

{randid, pad, htmlEscape, escape, starts, ends} = require 'joeson/lib/helpers'
{
  parse,
  NODES:joe
  HELPERS:{isWord,isVariable}
} = require 'joeson/src/joescript'
Node = require('joeson/src/node').createNodeClazz('ObjectNode')

# dependencies
require('joeson/src/translators/scope').install()
require('joeson/src/translators/javascript').install()
require('joeson/src/translators/etc').install()

# HELPERS FOR INTERPRETATION
isInteger = (n) -> n%1 is 0
isObject =  (o) -> o instanceof JObject or o instanceof JStub
@HELPERS = {isInteger, isObject}

# DEFINED AT BOTTOM OF FILE
RUNTIME = Set([JStub, JObject, JSingleton, JBoundFunc, Number, String, Function, Boolean])
RUNTIME_FUNC = Set([joe.Func, Function])

JStub = @JStub = clazz 'JStub', Node, ->
  init: ({@persistence, @id, @type}) ->
    assert.ok @id?, "Stub wants id"
  jsValue: ($, $$) ->
    cached1 = $$[@id]
    return cached1 if cached1?
    cached2 = $.kernel.cache[@id]
    return cached2.jsValue($, $$) if cached2?
    #throw new Error "DereferenceError: Broken reference: #{@}"
    return @
  __str__: ($) -> "<##{@id}>"
  toString: -> "<##{@id}>"

JObject = @JObject = clazz 'JObject', Node, ->

  @defineChildren
    id:       {type:String}
    creator:  {type:JUser, required:yes}
    data:     {type:{value:RUNTIME}}
    proto:    {type:RUNTIME}

  # data:   An Object
  # acl:    A JArray of JAccessControlItems
  #         NOTE: the acl has its own acl!
  # proto:  Both a workaround the native .__proto__ behavior,
  #         and a convenient way to create new JObjects w/ their prototypes.
  init: ({@id, @creator, @data, @acl, @proto}) ->
    assert.ok not @proto? or isObject @proto, "JObject wants JObject proto or null"
    assert.ok isObject @creator, "JObject wants JObject creator"
    if not @id?
      @id = randid()
      debug "Created new object #{@id}" if log
    @data ?= {}
    @data.__proto__ = null # detatch prototype

  # Event handling
  # Returns whether listener was added
  addListener: (listener) ->
    assert.ok listener.id?, "Listener needs an id"
    assert.ok listener.on?, "Listener needs an 'on' method"
    listeners = @listeners ?= {}
    return no if listeners[listener.id]?
    listeners[listener.id] = listener
    return yes

  # Emit an event from object to listeners
  emit: (event) ->
    assert.ok typeof event is 'object', 'Event must be an object'
    debug "emit: {type:#{event?.type},...} // listeners: #{Object.values @listeners}" if log # // #{inspect event}"
    return unless @listeners?
    event.sourceId = @id
    for id, listener of @listeners
      listener.on @, event

  ## Runtime functions ##
  
  # Asynchronous. See doc on the top of this file.
  __get__: ($, key, required=no) ->
    key = key.__key__($)
    $.will('read', this)
    if key is '__proto__'
      value = @proto
    else
      value = @data[key]
    debug "#{@}.__get__ #{key}, required=#{required} --> #{value} (#{typeof value};#{value?.constructor?.name})" if log
    if value?
      if value instanceof JStub
        return cached if cached=$.kernel.cache[value.id]
        assert.ok value.persistence?, "JObject::__get__ wants <JStub>.persistence"
        $.wait waitKey="load:#{value.id}"
        # Make a call to aynchronously fetch value
        value.persistence.loadJObject $.kernel, value.id, (err, obj) =>
          return $.throw 'InternalError', "Failed to load stub ##{value.id}:\n#{err.stack ? err}" if err?
          return $.throw 'ReferenceError', "#{key} is a broken stub." if required and not obj?
          # Replace stub with value in @data[key] (or @proto)
          if key is '__proto__'
            @proto = obj
          else
            @data[key] = obj
          $.last = obj
          $.resume waitKey
        return null # null means waiting
      else
        return value
    else if @proto?
      if @proto instanceof JStub
        $.push func:($, i9n, proto) ->
          $.pop()
          proto.__get__ $, key, required
        return @__get__ $, '__proto__'
      else
        return @proto.__get__ $, key, required
    else
      if (bridgedKey=@bridgedKeys?[key])?
        return @[bridgedKey]
      return $.throw 'ReferenceError', "#{key} is not defined" if required
      return JUndefined
  create: (creator, newData={}) ->
    new JObject creator:creator, data:newData, proto:@
  __create__: ($, newData) -> @create $.user, newData
  __hasOwn__: ($, key) ->
    $.will('read', this)
    return @data[key]?
  __set__: ($, key, value) ->
    key = key.__key__($)
    $.will('write', this)
    @data[key] = value
    @emit {thread:$,type:'set',key,value}
    return
  # an __update__ only happens for scope objects.
  __update__: ($, key, value) ->
    key = key.__key__($)
    $.will('write', this)
    if key is '__proto__'
      @proto = value
      @emit {thread:$,type:'update',key,value} # TODO more complicated, the chain was updated.
      return
    else if @data[key]?
      @data[key] = value
      @emit {thread:$,type:'update',key,value}
      return
    else if @proto?
      @emit {thread:$,type:'update',key,value} # TODO this is wrong... should be asynchronous.
      if @proto instanceof JStub
        $.push func:($, i9n, proto) ->
          $.pop()
          proto.__update__ $, key, value
        return @__get__ $, '__proto__'
      else
        return @proto.__update__ $, key, value
    else
      $.throw 'ReferenceError', "#{key} is not defined, cannot update."
  __keys__: ($) ->
    $.will('read', this)
    return Object.keys @data
  __iter__: ($) ->
    $.will('read', this)
    return new SimpleIterator Object.keys @data
  __num__:         ($) -> JNaN
  __add__:  ($, other) -> $.throw 'TypeError', "Can't add to object yet"
  __sub__:  ($, other) -> $.throw 'TypeError', "Can't subtract from object yet"
  __mul__:  ($, other) -> $.throw 'TypeError', "Can't multiply with object yet"
  __div__:  ($, other) -> $.throw 'TypeError', "Can't divide an object yet"
  __mod__:  ($, other) -> $.throw 'TypeError', "Can't modulate an object yet"
  __eq__:   ($, other) -> other instanceof JObject and other.id is @id
  __cmp__:  ($, other) -> $.throw 'TypeError', "Can't compare objects yet"
  __bool__: ($, other) -> yes
  __key__:         ($) -> $.throw 'TypeError', "Can't use object as a key"
  __str__:  ($, $$={}) ->
    return "<##{@id}>" if $$[@id]
    $$[@id] = yes
    dataPart = ("#{key.__str__($)}:#{value.__str__($, $$)}" for key, value of @data).join(',')
    return "{O|##{@id}@#{@creator.id} #{dataPart}}"
  __repr__: ($) ->
    # this is what it would look like in joescript
    # <"{#< ([key.__str__(),':',value.__repr__()] for key, value of @data).weave ', ', flattenItems:yes >}">
    $.jml(
      '{',
      $.jml(([key, ':', value.__repr__($)] for key, value of @data).weave(', ', flattenItems:yes)),
      '}'
    )
  jsValue: ($, $$={}) ->
    return $$[@id] if $$[@id]
    # console.log @serialize( (c={}; (n)->seen=c[n.id];c[n.id]=yes; not seen) )
    jsObj = $$[@id] = {}
    jsObj[key] = value.jsValue($, $$) for key, value of @data
    return jsObj
  toString: -> "[JObject ##{@id}]"

JArray = @JArray = clazz 'JArray', JObject, ->
  bridgedKeys: {
    'push': 'push'
  }

  init: ({id, creator, data, acl}) ->
    data ?= []
    data.__proto__ = null # detatch prototype
    @super.init.call @, {id, creator, data, acl}
  __get__: ($, key) ->
    $.will('read', this)
    if isInteger key
      return @data[key] ? JUndefined
    else
      return @super.__get__.call @, $, key
  __set__: ($, key, value) ->
    $.will('write', this)
    if isInteger key
      @data[key] = value
      @emit {thread:$,type:'set',key,value}
      return
    key = key.__key__($)
    @data[key] = value
    @emit {thread:$,type:'set',key,value}
    return
  __keys__: ($) ->
    $.will('read', this)
    return Object.keys(@data)
  __num__:        ($) -> JNaN
  __add__: ($, other) -> $.throw 'TypeError', "Can't add to array yet"
  __sub__: ($, other) -> $.throw 'TypeError', "Can't subtract from array yet"
  __mul__: ($, other) -> $.throw 'TypeError', "Can't multiply with array yet"
  __div__: ($, other) -> $.throw 'TypeError', "Can't divide an array yet"
  __mod__: ($, other) -> $.throw 'TypeError', "Can't modulate an array yet"
  __eq__:  ($, other) -> other instanceof JArray and other.id is @id
  __cmp__: ($, other) -> $.throw 'TypeError', "Can't compare arrays yet"
  __bool__: ($, other) -> yes
  __key__:        ($) -> $.throw 'TypeError', "Can't use an array as a key"
  __str__: ($, $$={}) ->
    return "<##{@id}>" if $$[@id]
    $$[@id] = yes
    return "{A|##{@id}@#{@creator.id} #{("#{if isInteger key then ''+key else key.__str__($)}:#{value.__str__($, $$)}" for key, value of @data).join(',')}}"
  __repr__: ($) ->
    arrayPart = (item.__repr__($) for item in @data).weave(',')
    dataPart = $.jml ([key, ':', value.__repr__($)] for key, value of @data when not isInteger key).weave(', ')
    if dataPart.length > 0
      return $.jml '[',arrayPart...,' ',dataPart,']'
    else
      return $.jml '[',arrayPart...,']'
  jsValue: ($, $$={}) ->
    return $$[@id] if $$[@id]
    jsObj = $$[@id] = []
    jsObj[key] = value.jsValue($, $$) for key, value of @data
    return jsObj
  toString: -> "[JArray ##{@id}]"
  push: ($, value) ->
    Array.prototype.push.call @data, value
    # also emit the key, to mitigate syncrony issues
    @emit {thread:$,type:'push',key:@data.length-1, value}
    return JUndefined

JAccessControlItem = @JAccessControlItem = clazz 'JAccessControlItem', ->
  # who:  User or JArray of users
  # what: Action or JArray of actions
  init: (@who, @what) ->
  toString: -> "[JAccessControlItem #{@who}: #{@what}]"

JUser = @JUser = clazz 'JUser', JObject, ->
  init: ({id, creator, name}) ->
    assert.equal typeof name, 'string', "@name not string" if name?
    creator ?= this
    @super.init.call @, {id, creator, data:{name}}
  name$: get: -> @data.name
  __str__:  ($, $$={}) ->
    return "<##{@id}>" if $$[@id]
    $$[@id] = yes
    dataPart = ("#{key.__str__($)}:#{value.__str__($, $$)}" for key, value of @data).join(',')
    return "{U|##{@id} #{dataPart}}"
  toString: -> "[JUser ##{@id} (#{@name})]"

JSingleton = @JSingleton = clazz 'JSingleton', ->
  init: (@name, @_jsValue) ->
  __get__:    ($, key) -> $.throw 'TypeError', "Cannot read property '#{key}' of #{@name}"
  __set__: ($, key, value) -> $.throw 'TypeError', "Cannot set property '#{key}' of #{@name}"
  __keys__:        ($) -> $.throw 'TypeError', "Cannot get keys of #{@name}"
  __iter__:        ($) -> $.throw 'TypeError', "Cannot get iterator of #{@name}"
  __num__:         ($) -> JNaN
  __add__:  ($, other) -> JNaN
  __sub__:  ($, other) -> JNaN
  __mul__:  ($, other) -> JNaN
  __div__:  ($, other) -> JNaN
  __mod__:  ($, other) -> JNaN
  __eq__:   ($, other) -> other instanceof JSingleton and @name is other.name
  __cmp__:  ($, other) -> $.throw 'TypeError', "Can't compare with #{@name}"
  __bool__: ($, other) -> no
  __key__:         ($) -> $.throw 'TypeError', "Can't use #{@name} as key"
  __str__:         ($) -> @name
  __repr__:        ($) -> @name
  jsValue: -> @_jsValue
  toString: -> "Singleton(#{@name})"

JNull       = @JNull      = JSingleton.null       = new JSingleton 'null', null
JUndefined  = @JUndefined = JSingleton.undefined  = new JSingleton 'undefined', undefined
JNaN        = @JNaN       = JSingleton.NaN        = new Number NaN # is this better, since op instructions carry over?
# JFalse/JTrue don't exist, just use native booleans.

# Actually, not always bound to a scope.
JBoundFunc = @JBoundFunc = clazz 'JBoundFunc', JObject, ->

  @defineChildren
    func:     {type:RUNTIME_FUNC, required:yes}
    scope:    {type:JObject}
    
  # func:    The joe.Func node, or a string for lazy parsing.
  # creator: The owner of the process that declared above function.
  # scope:   Runtime scope of process that declares above function.
  #          If scope is null, this function creates a new scope upon invocation.
  #          If scope is undefined, this function inherits the caller's scope.
  #           - for lazy lexical scoping.
  init: ({id, creator, acl, func, scope}) ->
    @super.init.call @, {id, creator, acl}
    assert.ok scope is JUndefined or scope is JNull or isObject scope, "JBoundFunc::__init__ wants null scope or a JObject, but got #{scope?.constructor.name}"
    @data.scope = scope
    if func instanceof joe.Func
      @func = func
      assert.ok func._origin.code?, "JBoundFunc::__init__ wants func._origin.code"
      @data.__code__ =  func._origin.code
      @data.__start__ = func._origin.start.pos
      @data.__end__ =   func._origin.end.pos
    # Convenient for creating functions procedurally
    else if typeof func is 'string'
      @data.__code__ =  func
      @data.__start__ = 0
      @data.__end__ =   func.length
    # Will get set later
    else if func is null
      'dontcare'
    else
      throw new Error "funky func"
  scope$:
    get: -> @data.scope,
    set: (scope) -> @data.scope = scope
  func$: get: ->
    assert.ok @data.__code__, "JBoundFunc::$func expects @data.__code__"
    assert.ok @data.__start__?, "JBoundFunc::$func expects @data.__start__"
    # TODO cache of code --> parsed nodes.
    node = parse @data.__code__
    node = node.toJSNode(toValue:yes).installScope().determine()
    assert.ok node instanceof joe.Block, "Expected Block at root node, but got #{node?.constructor?.name}"
    node = node.collectFunctions()
    assert.ok node._functions?, "Expected collected functions at node._functions"
    func = node._functions[@data.__start__]
    assert.ok func?, "Didn't get a func at the expected pos #{@data.__start__}. Code:\n#{@data.__code__}"
    return @func = func
  __str__: ($) -> "<F|##{@id}>"
  __repr__: ($) ->
    dataPart = ([key, ':', value.__repr__($)] for key, value of @data).weave(', ', flattenItems:yes)
    if dataPart.length > 0
      return $.jml('[JBoundFunc ', $.jml(dataPart), ']')
    else
      return "[JBoundFunc]"
  toString: -> "[JBoundFunc]"

SimpleIterator = clazz 'SimpleIterator', ->
  init: (@items) ->
    @length = @items.length
    @idx = 0
  next: ->
    if @idx < @length
      return @items[@idx]
    else throw 'StopIteration'

# Extensions on native objects
clazz.extend String,
  __get__:    ($, key) -> JUndefined
  __set__: ($, key, value) -> # pass
  __keys__:        ($) -> $.throw 'TypeError', "Object.keys called on non-object"
  __iter__:        ($) -> new SimpleIterator @valueOf()
  __num__:         ($) -> JNaN
  __add__:  ($, other) ->
    if typeof other is 'string' or other instanceof String
      @ + other
    else
      @ + other.__str__($)
  __sub__:  ($, other) -> $.throw 'NotImplementedError', "Implement me"
  __mul__:  ($, other) -> $.throw 'NotImplementedError', "Implement me"
  __div__:  ($, other) -> $.throw 'NotImplementedError', "Implement me"
  __mod__:  ($, other) -> $.throw 'NotImplementedError', "Implement me"
  __eq__:   ($, other) -> @valueOf() is other
  __cmp__:  ($, other) -> $.throw 'NotImplementedError', "Implement me"
  __bool__:        ($) -> @length > 0
  __key__:         ($) -> @valueOf()
  __str__:         ($) -> "\"#{escape @}\""
  __repr__:        ($) -> "\"#{escape @}\""
  jsValue: -> @valueOf()

clazz.extend Number,
  __get__:        ($) -> $.throw 'NotImplementedError', "Implement me"
  __set__:        ($) -> $.throw 'NotImplementedError', "Implement me"
  __keys__:       ($) -> $.throw 'NotImplementedError', "Implement me"
  __iter__:       ($) -> $.throw 'NotImplementedError', "Implement me"
  __num__:        ($) -> @valueOf() # prototype methods of native types, @ becomes object.
  __add__: ($, other) -> @valueOf() + other.__num__()
  __sub__: ($, other) -> @valueOf() - other.__num__()
  __mul__: ($, other) -> @valueOf() * other.__num__()
  __div__: ($, other) -> @valueOf() / other.__num__()
  __mod__: ($, other) -> @valueOf() % other.__num__()
  __eq__:  ($, other) -> @valueOf() is other
  __cmp__: ($, other) -> @valueOf() - other.__num__()
  __bool__:       ($) -> @valueOf() isnt 0
  __key__:        ($) -> @valueOf()
  __str__:        ($) -> ''+@
  __repr__:       ($) -> ''+@
  jsValue: -> @valueOf()

clazz.extend Boolean,
  __get__:        ($) -> $.throw 'NotImplementedError', "Implement me"
  __set__:        ($) -> $.throw 'NotImplementedError', "Implement me"
  __keys__:       ($) -> $.throw 'NotImplementedError', "Implement me"
  __iter__:       ($) -> $.throw 'NotImplementedError', "Implement me"
  __num__:        ($) -> JNaN
  __add__: ($, other) -> JNaN
  __sub__: ($, other) -> JNaN
  __mul__: ($, other) -> JNaN
  __div__: ($, other) -> JNaN
  __mod__: ($, other) -> JNaN
  __eq__:  ($, other) -> @valueOf() is other
  __cmp__: ($, other) -> JNaN
  __bool__:       ($) -> @valueOf()
  __key__:        ($) -> $.throw 'TypeError', "Can't use a boolean as a key"
  __str__:        ($) -> ''+@
  __repr__:       ($) -> ''+@
  jsValue: -> @valueOf()

clazz.extend Function, # native functions
  __get__:        ($) -> $.throw 'NotImplementedError', "Implement me"
  __set__:        ($) -> $.throw 'NotImplementedError', "Implement me"
  __keys__:       ($) -> $.throw 'NotImplementedError', "Implement me"
  __iter__:       ($) -> $.throw 'NotImplementedError', "Implement me"
  __num__:        ($) -> JNaN
  __add__: ($, other) -> JNaN
  __sub__: ($, other) -> JNaN
  __mul__: ($, other) -> JNaN
  __div__: ($, other) -> JNaN
  __mod__: ($, other) -> JNaN
  __eq__:  ($, other) -> @valueOf() is other
  __cmp__: ($, other) -> JNaN
  __bool__:       ($) -> yes
  __key__:        ($) -> $.throw 'TypeError', "Can't use a function as a key"
  __str__:        ($) -> "[NativeFunction ##{@id}]"
  __repr__:       ($) ->
    name = @name ? @_name
    if name
      "[NativeFunction: #{name}]"
    else
      "[NativeFunction]"
  jsValue: -> @valueOf()

# EXPORTS
@NODES = {
  JStub, JObject, JArray, JUser, JSingleton, JNull, JUndefined, JNaN, JBoundFunc
}
