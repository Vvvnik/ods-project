#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const os = require('os');
const { parseStringPromise } = require('xml2js');

// Парсинг аргументов командной строки
const args = process.argv.slice(2);
let inputDir = '';
let outputDir = '';
let format = 'svg';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--in' && i + 1 < args.length) {
    inputDir = args[i + 1];
    i++;
  } else if (args[i] === '--out' && i + 1 < args.length) {
    outputDir = args[i + 1];
    i++;
  } else if (args[i] === '--format' && i + 1 < args.length) {
    format = args[i + 1];
    i++;
  }
}

if (!inputDir || !outputDir) {
  console.error('❌ Использование: node drawio_to_img.js --in <input_dir> --out <output_dir> [--format png|svg]');
  process.exit(1);
}

// Определяем правильный путь к draw.io в зависимости от ОС
const DRAWIO_PATH = os.platform() === 'darwin' 
  ? '/Applications/draw.io.app/Contents/MacOS/draw.io'
  : 'draw.io';

// Функция для очистки названия файла
function sanitizeFileName(fileName) {
  return fileName
    .replace(/й/g, 'и')
    .replace(/ё/g, 'е')
    .replace(/\s+/g, '_')
    .replace(/[\/\\:*?"<>|]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '');
}

/**
 * draw.io экспортирует style с color-scheme и CSS light-dark(); Яндекс.Браузер
 * часто ломает такой SVG. Оставляем «светлую» ветку light-dark(a, b) → a.
 */
function normalizeSvgForLegacyBrowsers(svgContent) {
  let s = svgContent;
  // Убрать color-scheme на корне и в style-блоках
  s = s.replace(/\s*color-scheme:\s*light\s+dark\s*;?/gi, '');
  s = s.replace(/\s*background:\s*transparent\s*;?\s*/gi, '');
  s = s.replace(/\s*background-color:\s*transparent\s*;?\s*/gi, '');
  // light-dark(light, dark) → light (несколько проходов на случай вложенности)
  const re = /light-dark\(\s*((?:[^()]|\([^)]*\))*)\s*,\s*((?:[^()]|\([^)]*\))*)\s*\)/g;
  let prev;
  do {
    prev = s;
    s = s.replace(re, '$1');
  } while (s !== prev);
  // Пустые style="" или style=";" подчистить
  s = s.replace(/\sstyle="\s*;*\s*"/g, '');
  return s;
}

// Функция для добавления белого фона в SVG (из старого скрипта)
function addWhiteBackground(svgContent) {
  // Удаляем только сообщение "Text is not SVG - cannot display", но сохраняем текст
  let fixed = svgContent.replace(/<switch><g requiredFeatures="http:\/\/www\.w3\.org\/TR\/SVG11\/feature#Extensibility"\/><a transform="translate\(0,-5\)" xlink:href="https:\/\/www\.drawio\.com\/doc\/faq\/svg-export-text-problems" target="_blank"><text text-anchor="middle" font-size="10px" x="50%" y="100%">Text is not SVG - cannot display<\/text><\/a><\/switch>/g, '');
  
  // Находим позицию после открывающего тега <svg>
  const svgTagEnd = fixed.indexOf('>', fixed.indexOf('<svg'));
  if (svgTagEnd === -1) return fixed;
  
  // Извлекаем атрибуты viewBox для определения размеров
  const viewBoxMatch = fixed.match(/viewBox="([^"]+)"/);
  if (!viewBoxMatch) return fixed;
  
  const viewBox = viewBoxMatch[1].split(' ');
  const width = parseFloat(viewBox[2]);
  const height = parseFloat(viewBox[3]);
  
  // Создаем белый прямоугольник фона
  const whiteBackground = `\n  <rect width="${width}" height="${height}" fill="white" stroke="none"/>`;
  
  // Вставляем белый фон после открывающего тега <svg>
  return fixed.slice(0, svgTagEnd + 1) + whiteBackground + fixed.slice(svgTagEnd + 1);
}

const execWithTimeout = (cmd, args, options = {}) =>
  new Promise((resolve, reject) => {
    const child = execFile(cmd, args, { ...options, timeout: 15000 }, (error, stdout, stderr) => {
      if (error) {
        reject(error);
      } else {
        resolve({ stdout, stderr });
      }
    });
  });

async function convertDrawioToSvg(inputPath, outputDir, format) {
  fs.mkdirSync(outputDir, { recursive: true });

  const xmlContent = fs.readFileSync(inputPath, 'utf8');
  const parsed = await parseStringPromise(xmlContent);
  
  if (parsed.mxfile && parsed.mxfile.diagram) {
    const diagrams = Array.isArray(parsed.mxfile.diagram) 
      ? parsed.mxfile.diagram 
      : [parsed.mxfile.diagram];
    
    console.log(`  📄 Обработка: ${path.basename(inputPath)} → ${diagrams.length} страниц`);
    
    for (let i = 0; i < diagrams.length; i++) {
      const diagram = diagrams[i];
      const diagramName = diagram.$.name || `page_${i + 1}`;
      const sanitizedName = sanitizeFileName(diagramName);
      // Если это один файл, используем его имя, иначе добавляем имя диаграммы
      const baseFileName = path.basename(inputPath, '.drawio');
      const fileName = diagrams.length === 1 ? baseFileName : `${baseFileName}_${sanitizedName}`;
      const outputPath = path.join(outputDir, `${fileName}.${format}`);
      
      try {
        const tempFile = path.join(os.tmpdir(), `temp_${Date.now()}.drawio`);
        const tempXml = {
          mxfile: {
            $: parsed.mxfile.$,
            diagram: [diagram]
          }
        };
        
        const { Builder } = require('xml2js');
        const builder = new Builder();
        fs.writeFileSync(tempFile, builder.buildObject(tempXml));
        
        await execWithTimeout(DRAWIO_PATH, [
          '--export',
          '--format', format,
          '--output', outputPath,
          tempFile
        ]);
        
        fs.unlinkSync(tempFile);
        
        // Если это SVG, добавляем белый фон
        if (format === 'svg') {
          const svgContent = fs.readFileSync(outputPath, 'utf8');
          const fixedSvgContent = normalizeSvgForLegacyBrowsers(addWhiteBackground(svgContent));
          fs.writeFileSync(outputPath, fixedSvgContent);
        }
        
        console.log(`    ✅ ${sanitizedName}.${format}`);
        
      } catch (error) {
        console.error(`❌ Ошибка при конвертации ${diagramName}:`, error.message);
      }
    }
  } else {
    // Если нет страниц, конвертируем весь файл
    const fileName = path.basename(inputPath, '.drawio');
    const outputPath = path.join(outputDir, `${fileName}.${format}`);
    
    try {
      const args = [
        '-x', inputPath,
        '-f', format,
        '-o', outputPath
      ];
      
      // Для SVG добавляем параметры для включения текста
      if (format === 'svg') {
        args.push('--embed-fonts');
      }
      
      const { stdout } = await execWithTimeout(DRAWIO_PATH, args);
      
      // Если это SVG, добавляем белый фон
      if (format === 'svg') {
        const svgContent = fs.readFileSync(outputPath, 'utf8');
        const fixedSvgContent = normalizeSvgForLegacyBrowsers(addWhiteBackground(svgContent));
        fs.writeFileSync(outputPath, fixedSvgContent);
      }
      
      console.log(`    ✅ ${fileName}.${format}`);
      
    } catch (error) {
      console.error(`❌ Ошибка при конвертации:`, error.message);
    }
  }
}

async function walkAndConvert(inputPath, outputDir) {
  let drawioFiles = [];
  
  // Проверяем, это файл или папка
  const stat = fs.statSync(inputPath);
  if (stat.isFile()) {
    // Если это файл, обрабатываем его
    if (inputPath.endsWith('.drawio')) {
      drawioFiles = [inputPath];
    } else {
      console.log('ℹ️  Файл не является .drawio файлом');
      return;
    }
  } else if (stat.isDirectory()) {
    // Если это папка, ищем все .drawio файлы
    drawioFiles = fs.readdirSync(inputPath)
      .filter(file => file.endsWith('.drawio'))
      .map(file => path.join(inputPath, file));
    
    if (drawioFiles.length === 0) {
      console.log('ℹ️  .drawio файлы не найдены');
      return;
    }
  } else {
    console.log('❌ Путь не является файлом или папкой');
    return;
  }
  
  for (const drawioFile of drawioFiles) {
    await convertDrawioToSvg(drawioFile, outputDir, format);
  }
}

async function main() {
  console.log(`🎨 Рендеринг Draw.io → ${format.toUpperCase()}...`);
  console.log(`📁 Входной путь: ${inputDir}`);
  console.log(`📁 Выходная папка: ${outputDir}`);
  
  try {
    await walkAndConvert(inputDir, outputDir);
    console.log('✅ Все файлы обработаны.');
  } catch (error) {
    console.error('❌ Ошибка:', error.message);
  }
}

main().catch(console.error);