// taco_db.dart
// Camada de dados da TACO. Colar em lib/data/ e usar. Nao precisa saber SQL.
//
// Dependencias (pubspec.yaml):  sqflite, path
// Asset (pubspec.yaml):         assets/taco.db
//
// Uso:
//   final taco = TacoDb();
//   final lista = await taco.buscar('arroz');
//   final macros = lista.first.porGramas(150);   // macros de 150 g
//   print(macros.kcal);

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Macronutrientes. Valores nulos na TACO viram 0.
class Macros {
  final double kcal, proteina, carbo, gordura;
  const Macros({
    this.kcal = 0,
    this.proteina = 0,
    this.carbo = 0,
    this.gordura = 0,
  });

  Macros operator +(Macros o) => Macros(
    kcal: kcal + o.kcal,
    proteina: proteina + o.proteina,
    carbo: carbo + o.carbo,
    gordura: gordura + o.gordura,
  );

  Macros operator *(double f) => Macros(
    kcal: kcal * f,
    proteina: proteina * f,
    carbo: carbo * f,
    gordura: gordura * f,
  );

  @override
  String toString() =>
      'Macros(kcal: ${kcal.toStringAsFixed(1)}, P: ${proteina.toStringAsFixed(1)}, '
      'C: ${carbo.toStringAsFixed(1)}, G: ${gordura.toStringAsFixed(1)})';
}

/// Fibra em gramas; demais em miligramas. Valores nulos na TACO viram 0.
class Micros {
  final double fibra, calcio, manganes, ferro, sodio, potassio, zinco;
  const Micros({
    this.fibra = 0,
    this.calcio = 0,
    this.manganes = 0,
    this.ferro = 0,
    this.sodio = 0,
    this.potassio = 0,
    this.zinco = 0,
  });

  Micros operator +(Micros o) => Micros(
    fibra: fibra + o.fibra,
    calcio: calcio + o.calcio,
    manganes: manganes + o.manganes,
    ferro: ferro + o.ferro,
    sodio: sodio + o.sodio,
    potassio: potassio + o.potassio,
    zinco: zinco + o.zinco,
  );

  Micros operator *(double f) => Micros(
    fibra: fibra * f,
    calcio: calcio * f,
    manganes: manganes * f,
    ferro: ferro * f,
    sodio: sodio * f,
    potassio: potassio * f,
    zinco: zinco * f,
  );
}

class Alimento {
  final int id;
  final String nome;
  final String? categoria;
  final String? preparo;

  /// Macros por 100 g (padrao da TACO).
  final Macros por100g;

  /// Fibra, calcio, manganes, ferro, sodio, potassio e zinco por 100 g.
  final Micros micros100g;

  /// true se algum macro nao foi analisado (NA na TACO).
  final bool incompleto;

  /// Campos sem dado na TACO. Nomes: kcal, proteina_g, carbo_g, gordura_g,
  /// fibra_g, calcio_mg, manganes_mg, ferro_mg, sodio_mg, potassio_mg, zinco_mg.
  /// Use para mostrar "sem dado" em vez de "0".
  final Set<String> semDado;

  const Alimento({
    required this.id,
    required this.nome,
    this.categoria,
    this.preparo,
    required this.por100g,
    this.micros100g = const Micros(),
    this.incompleto = false,
    this.semDado = const {},
  });

  /// Macros para uma quantidade em gramas. Ex.: banana 120 g.
  Macros porGramas(double gramas) => por100g * (gramas / 100);

  /// Fibra e minerais para uma quantidade em gramas.
  Micros microsPorGramas(double gramas) => micros100g * (gramas / 100);
}

/// Alimento + quantidade em gramas. Ja calcula tudo para essa quantidade.
/// Ex.: Porcao(iogurte, 170).macros.kcal
class Porcao {
  final Alimento alimento;
  final double gramas;
  const Porcao(this.alimento, this.gramas);

  Macros get macros => alimento.porGramas(gramas);
  Micros get micros => alimento.microsPorGramas(gramas);
}

/// Sugestao de troca: outra porcao com calorias parecidas.
class Substituicao {
  final Porcao porcao;

  /// Quanto menor, mais parecido com o original (macros + micros).
  final double distancia;
  const Substituicao(this.porcao, this.distancia);
}

class TacoDb {
  static const _asset = 'assets/taco.db';
  static const _arquivo = 'taco.db';

  Database? _db;

  Future<Database> _abrir() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final caminho = join(dir, _arquivo);
    if (!await File(caminho).exists()) {
      final bytes = await rootBundle.load(_asset);
      await File(caminho).writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }
    return _db = await openDatabase(caminho, readOnly: true);
  }

  /// Busca por nome, ignora acento e maiusculas. Ex.: buscar('feijao').
  Future<List<Alimento>> buscar(String texto, {int limite = 30}) async {
    final db = await _abrir();
    final rows = await db.query(
      'alimento',
      where: 'nome_busca LIKE ?',
      whereArgs: ['%${_semAcento(texto)}%'],
      orderBy: 'nome_busca',
      limit: limite,
    );
    return rows.map(_deLinha).toList();
  }

  Future<Alimento?> porId(int id) async {
    final db = await _abrir();
    final rows = await db.query('alimento', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _deLinha(rows.first);
  }

  /// Alimentos da mesma categoria, do mais parecido em kcal para o menos.
  Future<List<Alimento>> substitutos(
    Alimento original, {
    int limite = 5,
  }) async {
    final db = await _abrir();
    final rows = await db.rawQuery(
      '''
      SELECT * FROM alimento
      WHERE categoria = ? AND id != ? AND kcal IS NOT NULL
      ORDER BY ABS(kcal - ?) ASC
      LIMIT ?
    ''',
      [original.categoria, original.id, original.por100g.kcal, limite],
    );
    return rows.map(_deLinha).toList();
  }

  /// Sugere trocas para [original] na quantidade [gramas].
  ///
  /// Para cada candidato (mesma categoria): calcula quantas gramas dele
  /// dao as MESMAS calorias do original, arredonda para multiplo de 5 g e
  /// ordena pelo quanto macros e micros ficam parecidos.
  Future<List<Substituicao>> substituir(
    Alimento original,
    double gramas, {
    int limite = 5,
    double fatorMin = 0.3, // evita porcao absurdamente pequena
    double fatorMax = 3.0, // evita porcao absurdamente grande
    bool mesmaCategoria = true,
  }) async {
    final kcalAlvo = original.por100g.kcal * gramas / 100;
    if (kcalAlvo <= 0) return [];

    final usaCategoria = mesmaCategoria && original.categoria != null;
    final db = await _abrir();
    final rows = await db.rawQuery(
      'SELECT * FROM alimento WHERE id != ? AND kcal IS NOT NULL AND kcal > 0 '
      '${usaCategoria ? 'AND categoria = ?' : ''}',
      [original.id, if (usaCategoria) original.categoria],
    );

    final base = Porcao(original, gramas);
    final resultado = <Substituicao>[];

    for (final r in rows) {
      final a = _deLinha(r);
      final g = ((kcalAlvo / a.por100g.kcal * 100) / 5).round() * 5.0;
      if (g < 5) continue;
      final fator = g / gramas;
      if (fator < fatorMin || fator > fatorMax) continue;

      final cand = Porcao(a, g);
      var dist = 0.0;
      var comparados = 0;
      for (final campo in _referencia.keys) {
        if (original.semDado.contains(campo) || a.semDado.contains(campo)) {
          continue; // nao compara o que a TACO nao mediu
        }
        dist +=
            (_valor(cand, campo) - _valor(base, campo)).abs() /
            _referencia[campo]!;
        comparados++;
      }
      if (comparados == 0) continue;
      resultado.add(Substituicao(cand, dist));
    }

    resultado.sort((x, y) => x.distancia.compareTo(y.distancia));
    return resultado.take(limite).toList();
  }

  // Valores de referencia (aprox.) usados so para dar peso parecido a
  // nutrientes de escalas diferentes. Podem ser ajustados.
  static const _referencia = <String, double>{
    'proteina_g': 50,
    'carbo_g': 300,
    'gordura_g': 65,
    'fibra_g': 25,
    'calcio_mg': 1000,
    'manganes_mg': 2.3,
    'ferro_mg': 14,
    'sodio_mg': 2300,
    'potassio_mg': 3500,
    'zinco_mg': 7,
  };

  static double _valor(Porcao p, String campo) {
    final m = p.macros, u = p.micros;
    switch (campo) {
      case 'proteina_g':
        return m.proteina;
      case 'carbo_g':
        return m.carbo;
      case 'gordura_g':
        return m.gordura;
      case 'fibra_g':
        return u.fibra;
      case 'calcio_mg':
        return u.calcio;
      case 'manganes_mg':
        return u.manganes;
      case 'ferro_mg':
        return u.ferro;
      case 'sodio_mg':
        return u.sodio;
      case 'potassio_mg':
        return u.potassio;
      default:
        return u.zinco;
    }
  }

  Future<List<String>> categorias() async {
    final db = await _abrir();
    final rows = await db.rawQuery(
      'SELECT DISTINCT categoria FROM alimento WHERE categoria IS NOT NULL ORDER BY categoria',
    );
    return rows.map((r) => r['categoria'] as String).toList();
  }

  /// Soma macros de varios itens: [(alimento, gramas), ...]
  Macros somar(List<(Alimento, double)> itens) =>
      itens.fold(const Macros(), (acc, i) => acc + i.$1.porGramas(i.$2));

  /// Soma fibra e minerais de varios itens: [(alimento, gramas), ...]
  Micros somarMicros(List<(Alimento, double)> itens) =>
      itens.fold(const Micros(), (acc, i) => acc + i.$1.microsPorGramas(i.$2));

  // ---- internos ----
  Alimento _deLinha(Map<String, Object?> r) {
    double? n(String c) => (r[c] as num?)?.toDouble();
    final k = n('kcal'),
        p = n('proteina_g'),
        c = n('carbo_g'),
        g = n('gordura_g');
    const campos = [
      'kcal',
      'proteina_g',
      'carbo_g',
      'gordura_g',
      'fibra_g',
      'calcio_mg',
      'manganes_mg',
      'ferro_mg',
      'sodio_mg',
      'potassio_mg',
      'zinco_mg',
    ];
    final semDado = {
      for (final campo in campos)
        if (r[campo] == null) campo,
    };
    return Alimento(
      id: r['id'] as int,
      nome: r['nome'] as String,
      categoria: r['categoria'] as String?,
      preparo: r['preparo'] as String?,
      por100g: Macros(
        kcal: k ?? 0,
        proteina: p ?? 0,
        carbo: c ?? 0,
        gordura: g ?? 0,
      ),
      micros100g: Micros(
        fibra: n('fibra_g') ?? 0,
        calcio: n('calcio_mg') ?? 0,
        manganes: n('manganes_mg') ?? 0,
        ferro: n('ferro_mg') ?? 0,
        sodio: n('sodio_mg') ?? 0,
        potassio: n('potassio_mg') ?? 0,
        zinco: n('zinco_mg') ?? 0,
      ),
      incompleto: k == null || p == null || c == null || g == null,
      semDado: semDado,
    );
  }

  static String _semAcento(String t) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in t.toLowerCase().trim().split('')) {
      final i = de.indexOf(ch);
      b.write(i >= 0 ? para[i] : ch);
    }
    return b.toString();
  }
}
