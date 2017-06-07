# tests/CMStest.rb

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'minitest/reporters'
require 'redcarpet'
require 'fileutils'

Minitest::Reporters.use!

require_relative '../cms'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def create_document(name, content = '')
    File.open(File.join(data_path, name), 'w') do |file|
      file.write(content)
    end
  end

  def expected_error
    'And you are? You must be signed in to do that.'
  end

  def session
    last_request.env['rack.session']
  end

  def app
    Sinatra::Application
  end

  def admin_session
    { 'rack.session' => { user: 'admin' } }
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def test_index
    create_document 'about.md'
    create_document 'changes.txt'
    create_document 'history.txt'

    get '/'
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, '<a href = "/about.md">about.md'
    assert_includes last_response.body, '<a href = "/changes.txt">changes.txt'

    assert_includes last_response.body, 'Sign In'
    assert_includes last_response.body, 'Sign Up'
  end

  def test_markdown_read
    create_document 'about.md', '#But it&#39;s just not'

    get '/about.md'
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, '<h1>But it&#39;s just not'
  end

  def test_plaintext_read
    create_document 'changes.txt', 'Marx suggests the use of neodialectic discourse'

    get '/changes.txt'
    assert_equal 200, last_response.status
    assert_equal 'text/plain', last_response['Content-Type']
    assert_includes last_response.body, 'Marx suggests the use of neodialectic discourse'
  end

  def test_document_not_found
    get '/notafile.ext'

    assert_equal 302, last_response.status
    assert_equal 'notafile.ext does not exist.', session[:error]

    follow_redirect!
    assert_equal 200, last_response.status
    assert_nil session[:error]
  end

  def test_edit_content_page
    create_document 'changes.txt', 'Marx suggests the use of neodialectic discourse'

    get '/changes.txt/edit', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Marx suggests the use of neodialectic discourse'
  end

  def test_edit_content_post
    create_document 'delete.txt', 'boogiewoogie'

    post '/delete.txt/edit', { file_content: 'get down' }, admin_session

    assert_equal 302, last_response.status
    assert_equal 'delete.txt has been updated.', session[:success]

    follow_redirect!

    get '/delete.txt'
    assert_includes last_response.body, 'get down'
  end

  def test_new_doc_form
    get '/new', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Enter the name for your new file:'
  end

  def test_create_doc
    post '/new', { file_name: 'new.txt' }, admin_session
    assert_equal 302, last_response.status
    assert_equal 'new.txt has been created.', session[:success]
    follow_redirect!

    get '/'
    assert_includes last_response.body, 'new.txt'
    refute_includes last_response.body, 'new.txt has been created.'
  end

  def test_create_doc_errors
    post '/new', { file_name: '' }, admin_session
    assert_includes last_response.body, 'A name is required.'

    post '/new', file_name: 'no_ext'
    assert_includes last_response.body, 'File must have extension .txt or .md'

    post '/new', file_name: 'wrong_ext.virus'
    assert_includes last_response.body, 'File must have extension .txt or .md'

    # test dupe protection and whitespace strip
    post '/new', file_name: '    new.txt    '
    post '/new', file_name: 'new.txt'
    assert_includes last_response.body, 'File already exists.'
  end

  def test_delete_file
    create_document 'delete_me.txt'
    get '/', {}, admin_session
    assert_includes last_response.body, 'delete_me.txt</a>'
    post '/delete_me.txt/delete'
    assert_equal 302, last_response.status
    assert_equal 'delete_me.txt was deleted.', session[:success]
    follow_redirect!
    refute_includes last_response.body, 'delete_me.txt</a>'
    assert_nil session[:success]
  end

  def test_login_page
    get '/user/login'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Go ahead and log in'
  end

  def test_bad_u_bad_p
    post '/user/login', username: 'wrong_u', password: 'so wrong'
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid Credentials'
    assert_includes last_response.body, 'wrong_u'
  end

  def test_bad_u_good_p
    post '/user/login', username: 'wrong_u', password: 'secret'
    assert_includes last_response.body, 'Invalid Credentials'
    assert_includes last_response.body, 'wrong_u'
  end

  def test_good_u_bad_p
    post '/user/login', username: 'admin', password: 'so wrong'
    assert_includes last_response.body, 'Invalid Credentials'
    assert_includes last_response.body, 'admin'
  end

  def test_successful_login
    post '/user/login', username: 'admin', password: 'secret'
    assert_equal 302, last_response.status
    assert_equal 'Welcome, admin! Hang out a while!', session[:success]

    get '/'
    assert_includes last_response.body, 'Sign Out'
    assert_nil session[:success]
  end

  def test_logout
    post '/user/login', username: 'admin', password: 'secret'

    post '/user/logout'
    assert_equal 302, last_response.status

    follow_redirect!
    assert_includes last_response.body, 'Bye!'

    get '/'
    refute_includes last_response.body, 'Bye!'
  end

  def test_logged_out_edit
    create_document 'test.me'

    get '/test.me/edit'
    assert_equal 302, last_response.status
    assert_equal expected_error, session[:error]

    post '/test.me/edit'
    assert_equal 302, last_response.status
    assert_equal expected_error, session[:error]
  end

  def test_logged_out_file_delete
    create_document 'test.me'

    post '/test.me/delete'
    assert_equal 302, last_response.status
    assert_equal expected_error, session[:error]
  end

  def test_logged_out_file_edit
    create_document 'test.me'

    get '/new'
    assert_equal 302, last_response.status
    assert_equal expected_error, session[:error]

    post '/new'
    assert_equal 302, last_response.status
    assert_equal expected_error, session[:error]
  end

  def test_new_user_page
    get '/user/new'
    assert_includes last_response.body, 'Sign Up</button>'
  end

  def test_new_user_signup
    # copies the user file, creates the new user, then restores the file from copy
    user_copy = File.read(user_path)
    post '/user/new', username: 'testy', pass1: 'test', pass2: 'test'
    File.open(user_path, 'w') { |file| file.write(user_copy) }

    assert_equal 302, last_response.status
    assert_equal 'Account created. Welcome new user!', session[:success]
    assert_equal 'testy', session[:user]
  end

  def test_new_password_error
    post '/user/new', username: 'testy', pass1: 'test', pass2: 'not the same'

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Passwords gotta match, buddy.'
    assert_nil session[:user]
  end

  def test_new_user_dupe_username
    post '/user/new', username: 'admin', pass1: 'test', pass2: 'not the same'
    assert_includes last_response.body, 'Sorry, that name has already been taken'
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'admin'
    assert_nil session[:user]
  end
end
