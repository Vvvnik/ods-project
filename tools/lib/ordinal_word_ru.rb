module TitlePageOrdinalWord
  def ordinal_word_ru(n)
    units = {
      1 => 'первая', 2 => 'вторая', 3 => 'третья', 4 => 'четвертая', 5 => 'пятая',
      6 => 'шестая', 7 => 'седьмая', 8 => 'восьмая', 9 => 'девятая'
    }
  
    teens = {
      10 => 'десятая', 11 => 'одиннадцатая', 12 => 'двенадцатая', 13 => 'тринадцатая',
      14 => 'четырнадцатая', 15 => 'пятнадцатая', 16 => 'шестнадцатая',
      17 => 'семнадцатая', 18 => 'восемнадцатая', 19 => 'девятнадцатая'
    }
  
    tens_full = {
      20 => 'двадцатая', 30 => 'тридцатая', 40 => 'сороковая', 50 => 'пятидесятая'
    }
  
    return units[n] if units[n]
    return teens[n] if teens[n]
    return tens_full[n] if tens_full[n]
  
    if n < 100
      t = (n / 10) * 10
      u = n % 10
      if tens_full[t] && units[u]
        base = tens_full[t].sub(/ая$/, 'ь')
        return "#{base} #{units[u]}"
      end
    end
  
    n.to_s
  end
end
