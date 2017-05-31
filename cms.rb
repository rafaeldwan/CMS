require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'

# returns the correct path to files regardless of OS or running test
def data_path
  if ENV["RACK_ENV"] == 'test'
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

# creates a new document
def create_document(name, content = "")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

# loads the file correctly based on extension
def load_file_content(file)
  if File.extname(file) == ".md"
    render_markdown(file)
  else
    headers["Content-Type"] = "text/plain"
    File.read(file)
  end
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
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map{ |file| File.basename(file) }
end

# homepage, shows a list of files available with 'edit' option
get "/" do
  erb :index
end

# file creation page
get "/new" do
  erb :new_file
end

# create new file, tests for file ext, uniqueness, empty value
post "/new" do
  filename = params[:file_name].strip
  if filename == ""
    session[:error] = "A name is required."
    status 422
    erb :new_file
  elsif File.extname(filename) == ""
    session[:error] = "File must have an extension."
    status 422
    erb :new_file
  elsif @files.include? filename
    session[:error] = "File already exists."
    status 422
    erb :new_file
  else
    create_document(filename)
    session[:success] = "#{filename} has been created."
    redirect "/"
  end
end

# shows plaintext or .md file on screen
get "/:file" do
  file = File.join(data_path, params[:file])

  if File.exist?(file)
    load_file_content(file)
  else
    session[:error] = "#{params[:file]} does not exist."
    redirect "/"
  end
end

# edit screen for the selected file
get "/:file/edit" do
  @filename = params[:file]
  @file_path = File.join(data_path, params[:file])
  @content = File.read(@file_path)
  erb :edit_file
end

# submit edits for a file
post "/:file/edit" do
  @filename = params[:file]
  @file_path = File.join(data_path, params[:file])
  content = params[:file_content]

  File.write(@file_path, content)

  session[:success] = "#{@filename} has been updated."
  redirect "/"
end

post "/:file/delete" do
  filename = params[:file]
  file_path = File.join(data_path, filename)
  File.delete(file_path)
  session[:success] = "#{filename} was deleted."
  redirect "/"
end
