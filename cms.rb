
require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

# returns the correct path to files regardless of OS or running test
def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

# returns correct path to user file
def user_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users.yml', __FILE__)
  end
end

# loads test or production user file
def load_user_credentials
  credentials_path = user_path
  YAML.load_file(credentials_path)
end

# converts data to YAML and saves to user file
def save_user_credentials(data)
  credentials_path = user_path
  File.open(credentials_path, 'w') do |file|
    file.write(YAML.dump(data))
  end
end

# returns true if user and password are valid
def valid_credentials?(username, password)
  users = load_user_credentials

  hashed_p = BCrypt::Password.new users[username] if users[username]
  hashed_p && hashed_p == password
end

# creates a new document
def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

# loads the file correctly based on extension
def load_file_content(file)
  case File.extname(file)
  when '.md' then render_markdown(file)
  when '.txt' then
    headers['Content-Type'] = 'text/plain'
    File.read(file)
  end
end

# redirects with error unless user is logged in
def validate_permission
  return true if session[:user]
  session[:error] = 'And you are? You must be signed in to do that.'
  redirect '/'
end

configure do
  enable :sessions
  set :session_secret, 'secret' # normally set by env variable
  set :erb, escape_html: true
end

helpers do
  # creates an instance of Redcarpet to correctly render markdown
  def render_markdown(file)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(File.read(file))
  end
end

before do
  pattern = File.join(data_path, '*')
  @files = Dir.glob(pattern).map { |file| File.basename(file) }
end

# homepage, shows a list of files available with 'edit' option
get '/' do
  erb :index
end

# file creation page
get '/new' do
  validate_permission

  erb :new_file
end

# create new file, tests for file ext, uniqueness, empty value
post '/new' do
  validate_permission

  filename = params[:file_name].strip
  if filename == ''
    session[:error] = 'A name is required.'
    status 422
    erb :new_file
  elsif !['.txt', '.md'].include? File.extname(filename)
    session[:error] = 'File must have extension .txt or .md'
    status 422
    erb :new_file
  elsif @files.include? filename
    session[:error] = 'File already exists.'
    status 422
    erb :new_file
  else
    create_document(filename)
    session[:success] = "#{filename} has been created."
    redirect '/'
  end
end

# shows plaintext or .md file on screen
get '/:file' do
  file = File.join(data_path, File.basename(params[:file]))

  if File.exist?(file)
    load_file_content(file)
  else
    session[:error] = "#{params[:file]} does not exist."
    redirect '/'
  end
end

# edit screen for the selected file
get '/:file/edit' do
  validate_permission

  @filename = params[:file]
  @file_path = File.join(data_path, params[:file])
  @content = File.read(@file_path)
  erb :edit_file
end

# submit edits for a file
post '/:file/edit' do
  validate_permission

  @filename = params[:file]
  @file_path = File.join(data_path, params[:file])
  content = params[:file_content]

  File.write(@file_path, content)

  session[:success] = "#{@filename} has been updated."
  redirect '/'
end

# delete a file
post '/:file/delete' do
  validate_permission

  filename = params[:file]
  file_path = File.join(data_path, filename)

  File.delete(file_path)

  session[:success] = "#{filename} was deleted."
  redirect '/'
end

# user login page
get '/user/login' do
  erb :log_in
end

# process user login
post '/user/login' do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:user] = username
    session[:success] = "Welcome, #{username}! Hang out a while!"
    redirect '/'
  else
    session[:error] = 'Invalid Credentials. Boo. Booooooo.'
    status 422
    erb :log_in
  end
end

# sign out user
post '/user/logout' do
  session.delete(:user)
  session[:success] = 'You have been signed out. Bye!'
  redirect '/'
end

# new user signup form
get '/user/new' do
  erb :new_user
end

# process new user
post '/user/new' do
  users = load_user_credentials
  username = params[:username]
  if users[username]
    status 422
    session[:error] = 'Sorry, that name has already been taken'
    erb :new_user
  elsif params[:pass1] != params[:pass2]
    status 422
    session[:error] = 'Passwords gotta match, buddy.'
    erb :new_user
  else
    hashed_password = BCrypt::Password.create(params[:pass1].to_s).to_s
    users[username] = hashed_password
    save_user_credentials(users)
    session[:success] = 'Account created. Welcome new user!'
    session[:user] = username
    redirect '/'
  end
end
