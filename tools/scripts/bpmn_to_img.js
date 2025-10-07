#!/usr/bin/env node

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

// Парсинг аргументов командной строки
const args = process.argv.slice(2);
let inputDir = '';
let outputDir = '';
let format = 'png';

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
  console.error('❌ Использование: node bpmn_to_img.js --in <input_dir> --out <output_dir> [--format png|svg]');
  process.exit(1);
}

const VIEWER_PATH = 'file://' + path.resolve(__dirname, 'viewer.html');

async function convertBpmnFile(browser, bpmnPath, outputPath, format) {
  const page = await browser.newPage();
  const xml = fs.readFileSync(bpmnPath, 'utf8');

  await page.goto(VIEWER_PATH);
  await page.evaluate((xml) => window.loadDiagram(xml), xml);
  await page.waitForFunction('window.isDiagramLoaded === true');

  if (format === 'svg') {
    // Скрываем логотип BPMN.iO перед генерацией SVG
    await page.evaluate(() => {
      const allElements = document.querySelectorAll('*');
      allElements.forEach(element => {
        if (element.textContent && element.textContent.includes('BPMN.iO')) {
          element.style.display = 'none';
        }
      });
    });
    
    const svg = await page.evaluate(() => window.getSVG());
    fs.writeFileSync(outputPath, svg);
  } else if (format === 'png') {
    // Ждем загрузки диаграммы
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // Скрываем логотип BPMN.iO
    await page.evaluate(() => {
      // Ищем и скрываем элементы с текстом "BPMN.iO"
      const allElements = document.querySelectorAll('*');
      allElements.forEach(element => {
        if (element.textContent && element.textContent.includes('BPMN.iO')) {
          element.style.display = 'none';
        }
      });
      
      // Также скрываем элементы по селекторам, которые могут быть логотипом
      const logoSelectors = [
        'text[text-anchor="end"]',
        'text[font-family*="Arial"]',
        'text[font-size="12"]',
        'text[fill="#666"]'
      ];
      
      logoSelectors.forEach(selector => {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => {
          if (el.textContent && el.textContent.includes('BPMN.iO')) {
            el.style.display = 'none';
          }
        });
      });
    });
    
    // Получаем границы диаграммы для обрезки
    const clip = await page.evaluate(() => {
      // Ищем элементы BPMN диаграммы (прямоугольники, круги, ромбы)
      const bpmnElements = document.querySelectorAll('rect, circle, polygon, path');
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      let foundElements = 0;
      
      bpmnElements.forEach(element => {
        const rect = element.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          minX = Math.min(minX, rect.x);
          minY = Math.min(minY, rect.y);
          maxX = Math.max(maxX, rect.x + rect.width);
          maxY = Math.max(maxY, rect.y + rect.height);
          foundElements++;
        }
      });
      
      if (foundElements === 0) {
        console.log('Элементы диаграммы не найдены, используем весь viewport');
        return { x: 0, y: 0, width: 1200, height: 800 };
      }
      
      const padding = 20; // Отступы вокруг диаграммы
      const width = maxX - minX + padding * 2;
      const height = maxY - minY + padding * 2;
      
      console.log(`Найдено элементов диаграммы: ${foundElements}, область: ${width}x${height}`);
      
      return {
        x: Math.max(0, minX - padding),
        y: Math.max(0, minY - padding),
        width: Math.ceil(width),
        height: Math.ceil(height)
      };
    });
    
    console.log(`📐 Область диаграммы: ${clip.width}x${clip.height} в позиции (${clip.x}, ${clip.y})`);
    
    // Устанавливаем размер viewport достаточный для обрезки
    await page.setViewport({
      width: Math.max(1400, clip.width + clip.x + 200),
      height: Math.max(1000, clip.height + clip.y + 200),
      deviceScaleFactor: 2 // Увеличиваем разрешение для лучшего качества
    });
    
    // Делаем скриншот только области диаграммы
    await page.screenshot({
      path: outputPath,
      type: 'png',
      clip: clip
    });
  }

  await page.close();
}

async function walkAndConvert(inputDir, outputDir, browser) {
  const files = fs.readdirSync(inputDir);
  
  for (const file of files) {
    const inputPath = path.join(inputDir, file);
    const stat = fs.statSync(inputPath);
    
    if (stat.isDirectory()) {
      const subOutputDir = path.join(outputDir, file);
      fs.mkdirSync(subOutputDir, { recursive: true });
      await walkAndConvert(inputPath, subOutputDir, browser);
    } else if (path.extname(file) === '.bpmn') {
      const baseName = path.basename(file, '.bpmn');
      const outputFile = `${baseName}.${format}`;
      const outputPath = path.join(outputDir, outputFile);
      
      console.log(`  📄 Обработка: ${file} → ${outputFile}`);
      await convertBpmnFile(browser, inputPath, outputPath, format);
    }
  }
}

(async () => {
  console.log(`🎨 Рендеринг BPMN → ${format.toUpperCase()}...`);
  console.log(`📁 Входная папка: ${inputDir}`);
  console.log(`📁 Выходная папка: ${outputDir}`);
  
  if (!fs.existsSync(inputDir)) {
    console.error(`❌ Входная папка не найдена: ${inputDir}`);
    process.exit(1);
  }
  
  fs.mkdirSync(outputDir, { recursive: true });
  
  const browser = await puppeteer.launch({ headless: "new" });
  await walkAndConvert(inputDir, outputDir, browser);
  await browser.close();
  
  console.log('✅ Все файлы обработаны.');
})();
