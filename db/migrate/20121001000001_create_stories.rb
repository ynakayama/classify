class CreateStories < ActiveRecord::Migration

  def change
    create_table :stories do |t|
      t.string :text
      t.string :classify
      t.float  :social
      t.float  :politics
      t.float  :international
      t.float  :economics
      t.float  :electro
      t.float  :sports
      t.float  :entertainment
      t.float  :science

      t.timestamps
    end
  end
end
