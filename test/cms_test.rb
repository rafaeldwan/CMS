# tests/CMStest.rb

ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "minitest/reporters"
require "redcarpet"
require "fileutils"

Minitest::Reporters.use!

require_relative "../cms"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def app
    Sinatra::Application
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"
    create_document "history.txt"

    get "/"
      assert_equal 200, last_response.status
      assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
      assert_includes last_response.body, '<a href = "/about.md">about.md'
      assert_includes last_response.body, '<a href = "/changes.txt">changes.txt'
      assert_includes last_response.body, '<a href = "/history.txt">history.txt'
  end

  def test_markdown_read
    create_document "about.md", "<h1>But it&#39;s just not"

    get "/about.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>But it&#39;s just not"
  end

  def test_plaintext_read
    create_document "changes.txt", "Marx suggests the use of neodialectic discourse"

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Marx suggests the use of neodialectic discourse"
  end

  def test_document_not_found
    get "/notafile.ext"

    assert_equal 302, last_response.status
    # get last_response["Location"]
    follow_redirect!
    assert_equal 200, last_response.status
    assert_includes last_response.body, "notafile.ext does not exist"
  end

  def test_edit_content_correct
    create_document "changes.txt", "Marx suggests the use of neodialectic discourse"

    get "/changes.txt/edit"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Marx suggests the use of neodialectic discourse"
  end

  def test_edit_content_post
    create_document "delete.txt", "boogiewoogie"
    get "/delete.txt"

    assert_includes last_response.body, "boogiewoogie"

    post '/delete.txt/edit', file_content: "get down"

    assert_equal 302, last_response.status
    follow_redirect!
    assert_equal 200, last_response.status
    assert_includes last_response.body, "delete.txt has been updated."

    get '/delete.txt'
    assert_includes last_response.body, "get down"
  end

  def test_new_doc_form
    get "/new"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Enter the name for your new file:"
  end

  def test_create_doc
    post "/new", file_name: "new.new"
    assert_equal 302, last_response.status
    follow_redirect!
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new.new has been created."

    get "/"
    assert_includes last_response.body, "new.new"
  end

  def test_create_doc_errors
    post "/new", file_name: ""
    assert_includes last_response.body, "A name is required."

    post "/new", file_name: "no_ext"
    assert_includes last_response.body, "File must have an extension."

    # test dupe protection and whitespace strip
    post "/new", file_name: "    new.new    "
    post "/new", file_name: "new.new"
    assert_includes last_response.body, "File already exists."
  end

  def test_delete_file
    create_document 'delete_me.txt'
    get '/'
    assert_includes last_response.body, 'delete_me.txt</a>'
    post '/delete_me.txt/delete'
    assert_equal 302, last_response.status
    follow_redirect!
    assert_includes last_response.body, 'delete_me.txt was deleted.'
    refute_includes last_response.body, 'delete_me.txt</a>'
  end
end
