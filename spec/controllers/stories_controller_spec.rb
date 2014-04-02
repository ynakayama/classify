# -*- coding: utf-8 -*-

require File.dirname(__FILE__) + '/../spec_helper'

describe StoriesController, 'Stories' do
  fixtures :all

  context 'にアクセスする場合' do
    # login_admin

    def create
      post 'create' , :story => {
        "text"=>"ふが",
      }
    end

    describe '一覧表示' do
      it "一覧画面が表示される" do
        get 'index'
        response.should be_success
      end
    end

    describe '詳細' do
      it "詳細画面が表示される" do
        get 'show', :id => 1
        response.should be_success
      end
    end

    describe '新規作成' do
      it "新規作成画面が表示される" do
        get 'new'
        response.should be_success
      end
    end

    describe '作成' do
      it "作成処理が正常終了する" do
        create
        response.redirect_url.should == 'http://test.host/'
        response.header.should have_at_least(1).items
        response.body.should have_at_least(1).items
        flash[:notice].should_not be_nil
        flash[:notice].should == 'カテゴリ分類の判定は「経済」です'
      end

      it "新規レコードが作成される" do
        create
        content = Story.find(2)
        content.text.should == "ふが"
        content.classify.should == "経済"
      end
    end

  end
end
