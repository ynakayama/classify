# -*- encoding: utf-8 -*-

require 'naivebayes'
require 'MeCab'
require 'fluent-logger'
require 'sysadmin'
require 'singleton'

class Exclude
  include Singleton
  def initialize
    log_path      = "/home/fluent/.fluent/log"
    exclude_file  = "wordcount_exclude.txt"
    exclude_txt   = File.expand_path(File.join(log_path, exclude_file))
    @exclude      = Array.new

    open(exclude_txt) do |file|
      file.each_line do |line|
        @exclude << line.force_encoding("utf-8").chomp
      end
    end
  end

  def exclude
    @exclude
  end
end

class StoriesController < ApplicationController

  def new
    @story = Story.new

    respond_to do |format|
      format.html
      format.json { render json: @story }
    end
  end

  def show
    @story = Story.find(params[:id])

    respond_to do |format|
      format.html
      format.json { render json: @story }
    end
  end

  def create
    @run_date      = Date.today
    @pickup_date   = (@run_date - 1).strftime("%Y%m%d")
    @log_name      = "news.log.#{@pickup_date}_0.log"
    @wordcount     = "wordcount_#{@pickup_date}.txt"
    @train         = "category_map.txt"
    @hot_news      = "hotnews_#{@pickup_date}.txt"
    @log_path      = "/home/fluent/.fluent/log"
    @train_txt     = File.expand_path(File.join(@log_path, @train))

    @mecab = MeCab::Tagger.new("-Ochasen")
    @classifier = NaiveBayes::Classifier.new(:model => "multinomial")
    @exclude       = Exclude.instance.exclude
    puts_with_time("Exclude word's array is #{@exclude}")
    train_from_datasource

    @story = Story.new(story_params)
    @story.text = params[:story][:text].truncate_screen_width(1000, suffix = "")
    classify(@story.text)
    result = 'カテゴリ分類の判定は「' + @story.classify + '」です'

    respond_to do |format|
      session[:result]        = result
      session[:text]          = @story.text.truncate_screen_width(1000, suffix = "")
      session[:social]        = @story.social
      session[:politics]      = @story.politics
      session[:international] = @story.international
      session[:economics]     = @story.economics
      session[:electro]       = @story.electro
      session[:sports]        = @story.sports
      session[:entertainment] = @story.entertainment
      session[:science]       = @story.science
      session[:classify]      = @story.classify

      if Rails.env.production?
        @fluentd = Fluent::Logger::FluentLogger.open('classify',
          host = 'localhost', port = 9999)

        @fluentd.post('record', {
          :text          => @story.text.truncate_screen_width(1000, suffix = ""),
          :social        => @story.social,
          :politics      => @story.politics,
          :international => @story.international,
          :economics     => @story.economics,
          :electro       => @story.electro,
          :sports        => @story.sports,
          :entertainment => @story.entertainment,
          :science       => @story.science,
          :classify      => @story.classify
        })
      end

      if @story.save
        notice = "#{result}"
        format.html { redirect_to root_path,
          notice: notice }
        format.json { render json: @story, status: :created, location: @story }
      else
        format.html { render action: "new" }
        format.json { render json: @story.errors, status: :unprocessable_entity }
      end
    end
  end

  def index
    @stories = Story.page(params[:page]).order(id: :desc)

    respond_to do |format|
      format.html
      format.json { render json: @stories }
    end
  end

  private

  def puts_with_time(message)
    fmt = "%Y/%m/%d %X"
    puts "#{Time.now.strftime(fmt)}: #{message.force_encoding("utf-8")}"
  end

  def train(category)
    hits = {}
    exclude_count = 0
    open(@train_txt) do |file|
      file.each_line do |line|
        word, counts, social, politics, international, economics, electro, sports, entertainment, science, standard_deviation = line.force_encoding("utf-8").strip.split("\t")
        array = [social.to_i, politics.to_i, international.to_i, economics.to_i, electro.to_i, sports.to_i, entertainment.to_i, science.to_i]
        if array.max <= 100
          unless array[@train_num].to_i == 0
            #if array.max < 100
            #if counts.to_i == array.max or standard_deviation.to_f < 0.4
            if standard_deviation.to_f < 10.0
              unless @exclude.include?(word)
                if word =~ /[一-龠]/
                  hits.has_key?(word) ? hits[word] += array[@train_num].to_i * 3 : hits[word] = array[@train_num].to_i * 3
                elsif word =~ /^[A-Za-z].*/
                  hits.has_key?(word) ? hits[word] += array[@train_num].to_i : hits[word] = array[@train_num].to_i
                end
              end
            end
          end
        end
      end
    end
    @train_num += 1
    return hits
  end

  def train_from_datasource
    @train_num = 0
    @classifier.train("social",         train('category.social'))
    @classifier.train("politics",       train('category.politics'))
    @classifier.train("international",  train('category.international'))
    @classifier.train("economics",      train('category.economics'))
    @classifier.train("electro",        train('category.electro'))
    @classifier.train("sports",         train('category.sports'))
    @classifier.train("entertainment",  train('category.entertainment'))
    @classifier.train("science",        train('category.science'))
  end

  def classify(data)
    hits = {}
    result = {}
    pickup_nouns(data).each {|word|
      if word.length > 1
        if word =~ /[一-龠]/
          hits.has_key?(word) ? hits[word] += 3 : hits[word] = 3
        else
          hits.has_key?(word) ? hits[word] += 1 : hits[word] = 1
        end
      end
    }
    @classifier.classify(hits).each {|k, v|
      result[k] = (v / 1.0 * 100).round(2)
    }
    @story.social        = result["social"]
    @story.politics      = result["politics"]
    @story.international = result["international"]
    @story.economics     = result["economics"]
    @story.electro       = result["electro"]
    @story.sports        = result["sports"]
    @story.entertainment = result["entertainment"]
    @story.science       = result["science"]
    case result.max{|a, b| a[1] <=> b[1]}[0]
    when 'social'
      @story.classify = '社会'
    when 'politics'
      @story.classify = '政治'
    when 'international'
      @story.classify = '国際'
    when 'economics'
      @story.classify = '経済'
    when 'electro'
      @story.classify = '電脳'
    when 'sports'
      @story.classify = 'スポーツ'
    when 'entertainment'
      @story.classify = 'エンタメ'
    when 'science'
      @story.classify = '科学'
    else
      @story.classify = '不明'
    end
  end

  def pickup_nouns(string)
    node = @mecab.parseToNode(string)
    nouns = []
    while node
      if /^名詞/ =~ node.feature.force_encoding("utf-8").split(/,/)[0] then
        nouns.push(node.surface.force_encoding("utf-8"))
      end
      node = node.next
    end
    nouns
  end

  private
    def set_story
      @story = Story.find(params[:id])
    end

    def story_params
      params.require(:story).permit(:text)
    end
end

class String
  def truncate_screen_width(width , suffix = "...")
    i = 0
    self.each_char.inject(0) do |c, x|
      c += x.ascii_only? ? 1 : 2
      i += 1
      next c if c < width
      return self[0 , i] + suffix
    end
    return self
  end
end
