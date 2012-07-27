# Joescript Serialization Language
# Joeson is the parser, so this is called something else. JSL, why not?
{Grammar} = require 'sembly/src/joeson'
{
  NODES:{JObject, JArray, JUser, JUndefined, JNull, JNaN, JBoundFunc, JStub}
  GLOBALS:GLOBALS
  HELPERS:{isInteger,isObject}
} = require 'sembly/src/interpreter'


JSL = Grammar ({o, i, tokens}) -> [
  o ANY: [
    o NUMBER:       " /-?[0-9]+(\\.[0-9]+)?/ ", (it) -> Number it
    o STRING:       " '\"' (!'\"' &:(ESCSTR | .))* '\"'  ", (it) -> it.join ''
    o OBJ: [
      o             " '<' (type:[F] '|')? '#' id:ID '>' ", ({type,id}, $) ->
                      # Check client cache for existing JObject instance.
                      if $.env.cache
                        cached = $.env.cache[id]
                        return cached if cached?
                      return JStub {id,type}
      o             " '{' type:[OAU] '|#' id:ID ('@' creatorId:ID)? ' ' items:OBJ_ITEM*',' '}' ", ({type,id,creatorId,items}, $) ->
                      # NOTE: Even though the full object was given,
                      # it's possible that object is already present in client cache.
                      # This is because currently there is no server tracking of the client cache state.
                      if $.env.cache
                        cached = $.env.cache[id]
                        return cached if cached?
                      creator = $.env.cache[creatorId] ? new JStub {id:creatorId,type:'U'} if creatorId
                      switch type
                        when 'O' then obj = new JObject {id,creator}
                        when 'A' then obj = new JArray  {id,creator}
                        when 'U' then obj = new JUser   {id}
                        else return cb("Unexpected type of object w/ id #{id}: #{type}")
                      obj.data[key] = value for {key, value} in items
                      $.env.cache?[id] = obj if id?
                      $.env.newCallback?(obj)
                      return obj
    ]
    o BOOLEAN:      " 'true' | 'false' ", (it) -> it is 'true'
    o UNDEFINED:    " 'undefined' ", -> JUndefined
    o NAN:          " 'NaN' ", -> NaN
    o NULL:         " 'null' ", -> JNull
  ]
  i OBJ_ITEM:     " key:(NUMBER|STRING) ':' value:ANY "
  i ID:           " [a-zA-Z0-9]{1,24} ", (it) -> it.join ''
  i ESCSTR:       " '\\\\' . ", (it) -> {n:'\n', t:'\t', r:'\r'}[it] or it
  i '.':          " /[\\s\\S]/ "
]

@parse = JSL.parse
