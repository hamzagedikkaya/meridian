# "Contains" matching for free-text filters (the web's search, GET
# /api/v1/search, GET /api/v1/transactions?q=). ILIKE alone ignores case
# only as far as the database collation knows it, and under the C collation
# that is ASCII: "şeker" would miss "Şeker". So a column also matches when its Turkish
# fold contains the query's fold: Ç Ğ Ö Ş Ü Â Î Û lowered, and I, İ, ı
# and i read as one letter. Accents are not dropped ("kosu" does not
# find "Koşu"). % and _ in the query match themselves.
module TextMatching
  FOLD_FROM = "ÇĞİIÖŞÜÂÎÛı".freeze
  FOLD_TO = "çğiiöşüâîûi".freeze

  private

  # +columns+ of +model+ (attribute names) as text_match takes them.
  def matching(query, model, *columns)
    text_match(columns.map { |column| model.arel_table[column] }, query)
  end

  # An Arel condition: any of +columns+ (Arel attributes or functions)
  # contains +query+.
  def text_match(columns, query)
    raw = like_pattern(query)
    folded = like_pattern(fold_text(query))
    columns.map { |column| column.matches(raw).or(fold_column(column).matches(folded, nil, true)) }.reduce(:or)
  end

  def like_pattern(text)
    "%#{ActiveRecord::Base.sanitize_sql_like(text)}%"
  end

  def fold_text(text)
    text.tr(FOLD_FROM, FOLD_TO).downcase
  end

  def fold_column(column)
    translated = Arel::Nodes::NamedFunction.new(
      "translate", [ column, Arel::Nodes.build_quoted(FOLD_FROM), Arel::Nodes.build_quoted(FOLD_TO) ]
    )
    Arel::Nodes::NamedFunction.new("lower", [ translated ])
  end
end
