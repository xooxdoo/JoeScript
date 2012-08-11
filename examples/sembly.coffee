## Mandatory fibo                                                                                                                                                                                  
a = 1
b = 1
fibo = ->
  c = a
  a += b
  b = c
loop
  print fibo()
  return a if a > 1000

## Multithreaded
a = 1
print out = {current:0}
loop
  if a % 1000 is 0
    out.current = a
  a += 1

## Email?
@jae.send = (msg) ->
  @messages ||= []
  @messages.push msg
  'message sent'

@jae.read = ->
  msg = @messages.shift()
  if msg then msg else '-- no more --'

## Chat!
messages = []
input = {type:'editor', mode:'markdown', onSubmit: ({data:text}) -> messages.push text}
chat = [messages, submit:input]
chat.__class__ = 'hideKeys'
@chat = chat

## Forms?
form = {
  email:    {type:'input'}
  name:     {type:'input'}
  website:  {type:'input'}
}
form.onSubmit = ({data}) ->
  print data
form

## Index
it = ['Enter password:', {type:'input',key:'password'}]
it.__class__ = 'hideKeys'
it.onSubmit = ({screen, modules, data}) ->
  return unless data.password is 'hello'
  screen.length = 0 # clear
  screen.push modules
  screen.push command
@index = it

## @index

@signups or= []
signup = [
  'enter your email for an invite'
  {type:'input', key:'email'}
  'website?'
  {type:'input', key:'website'}
  'tell me something about you'
  {type:'editor', mode:'markdown', key:'about'}
]
signup.__class__ = 'hideKeys'
signup.onSubmit = ({data}) ->
  @signups.push data

login = [
  'password:',
  {type:'input', key:'password'},
]
login.__class__ = 'hideKeys'
login.onSubmit = ({screen, modules, data}) ->
  if data.password is 'hello'
    screen.length = 0 # clear
    screen.push modules
    screen.push command
  else
    screen.push "* wrong password :( *"
  
##
@index = {signup,login}


## WALK
walk = (obj, seen={}) ->
  return if seen[obj?id]
  seen[obj?id] = yes
  for key, value of obj
    if value?type is 'object'
      print "walking #{value?id}"
      walk(value, seen) if seen[value?id]
walk @index
