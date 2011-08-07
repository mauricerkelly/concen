require "test_helper"

class PageTest < ActiveSupport::TestCase
  test "should create page" do
    page = Fabricate "control_center/page"
    assert_not_nil page.id
  end

  test "should create child page" do
    page = Fabricate "control_center/page"
    child_page = page.children.create :title => "1984"
    assert_not_nil child_page.id
    assert_equal page.id, child_page.parent.id
  end

  test "should parse title from raw_text" do
    page = Fabricate "control_center/page", :title => nil, :raw_text => "Title: Page Title"
    assert_equal page.title, "Page Title"
  end

  test "should parse publish_time from raw_text" do
    raw_text = "Title: Page Title 2\n\nPublish Time: now"
    page = Fabricate "control_center/page", :title => nil, :raw_text => raw_text
    assert_not_nil page.publish_time
    assert_not_equal page.raw_text, raw_text
  end

  test "should parse multi content from raw_text and conver to html correctly" do
    raw_text = File.read "#{File.dirname(__FILE__)}/../support/raw_text/multi_content.txt"
    html = File.read("#{File.dirname(__FILE__)}/../support/raw_text/multi_content.html")
    page = Fabricate "control_center/page", :title => nil, :raw_text => raw_text
    assert_not_nil page.content
    assert_equal page.content.keys, ["part_1", "part_2"]
    assert_not_nil page.content_in_html("part_1")
    assert_not_nil page.content_in_html("part_2")
    assert_equal page.content_in_html("part_1") + page.content_in_html("part_2"), html
  end

  test "should parse content with SmartyPants supported entities and convert to html correctly" do
    raw_text_smartypants = File.read "#{File.dirname(__FILE__)}/../support/raw_text/smartypants.txt"
    raw_text_smartypants_escape = File.read "#{File.dirname(__FILE__)}/../support/raw_text/smartypants_escape.txt"
    assert_not_nil raw_text_smartypants
    assert_not_nil raw_text_smartypants_escape

    page1 = Fabricate "control_center/page", :title => nil, :raw_text => raw_text_smartypants
    assert_equal page1.content_in_html, page1.content_in_html("main")
    assert_equal page1.content_in_html, File.read("#{File.dirname(__FILE__)}/../support/raw_text/smartypants.html")

    page2 = Fabricate "control_center/page", :title => nil, :raw_text => raw_text_smartypants_escape
    assert_equal page2.content_in_html, page2.content_in_html("main")
    assert_equal page2.content_in_html, File.read("#{File.dirname(__FILE__)}/../support/raw_text/smartypants_escape.html")
  end

  test "should parse content with code blocks and convert to html correctly" do
    raw_text_code_blocks = File.read "#{File.dirname(__FILE__)}/../support/raw_text/code_blocks.txt"
    assert_not_nil raw_text_code_blocks

    page = Fabricate "control_center/page", :title => nil, :raw_text => raw_text_code_blocks
    assert_equal page.content_in_html, page.content_in_html("main")
    assert_equal page.content_in_html, File.read("#{File.dirname(__FILE__)}/../support/raw_text/code_blocks.html")
  end

  test "should have default_slug" do
    page = Fabricate "control_center/page"
    assert_not_nil page.default_slug
    assert page.default_slug.length > 0
  end

  test "should not be created without title" do
    page = Fabricate.build "control_center/page", :title => nil
    assert_raise(Mongoid::Errors::Validations) { page.save! }
		assert_equal page.errors[:title].first, "can't be blank"
  end

  test "should have authors" do
    page = Fabricate.build "control_center/page", :authors => ["user1", "user2", "user3"]
    assert_equal page.authors.count, 3
  end

  test "should get correct author_as_user" do
    user = Fabricate "control_center/user"
    page = Fabricate.build "control_center/page", :authors => [user.username, "user2"]
    assert_equal page.authors.count, 2
    assert_equal page.authors_as_user.count, 1
    assert page.authors_as_user.include?(user.reload), "Does not include a correct user."
  end

  test "should get the correct slug" do
    page = Fabricate "control_center/page", :title => "New Title"
    assert_equal page.slug, "new-title"
    page.write_attribute :slug, "new-slug"
    page.save
    assert_equal page.slug, "new-slug"
  end
end