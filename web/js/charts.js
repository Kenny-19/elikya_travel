/* charts.js — graphiques SVG sans dépendance (marche en file://).
   Elikya.charts.stackedColumns(el, { rows, series, format, label })
     rows   : [{ jour:'AAAA-MM-JJ', <clé série>: nombre, … }]
     series : [{ key, label, color:'var(--series-1)' }]  (ordre fixe des couleurs, jamais recyclé)
     format : fn(nombre) → texte (ex. montant en $)
   Règles (cf. skill dataviz) : un seul axe, colonnes ≤ 24 px à bout arrondi 4 px, écart de 2 px
   entre segments, grille fine discrète, légende toujours visible, info-bulle au survol, tableau. */
(function(){
  var NS = 'http://www.w3.org/2000/svg';
  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
  function el(tag, attrs){ var n = document.createElementNS(NS, tag); for(var k in attrs) n.setAttribute(k, attrs[k]); return n; }
  function compact(v){
    if(Math.abs(v) >= 1e6) return (v/1e6).toLocaleString('fr-FR',{maximumFractionDigits:1})+' M';
    if(Math.abs(v) >= 1e4) return (v/1e3).toLocaleString('fr-FR',{maximumFractionDigits:0})+' k';
    return v.toLocaleString('fr-FR');
  }
  function jourLong(k){ try{ return new Date(k+'T00:00:00').toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long'}); }catch(e){ return k; } }

  // colonne : segment du haut arrondi (4 px), base carrée
  function topRounded(x, y, w, h, r){
    r = Math.min(r, h, w/2);
    return 'M'+x+','+(y+h)+'V'+(y+r)+'Q'+x+','+y+' '+(x+r)+','+y+'H'+(x+w-r)+'Q'+(x+w)+','+y+' '+(x+w)+','+(y+r)+'V'+(y+h)+'Z';
  }

  function stackedColumns(host, opts){
    var rows = opts.rows || [], series = opts.series || [], fmt = opts.format || String;
    host.innerHTML = '';
    host.classList.add('viz');

    // légende (≥ 2 séries → toujours présente)
    var legend = document.createElement('div');
    legend.className = 'viz-legend';
    legend.innerHTML = series.map(function(s){ return '<span><i style="background:'+s.color+'"></i>'+esc(s.label)+'</span>'; }).join('');
    host.appendChild(legend);

    var total = function(r){ return series.reduce(function(a, s){ return a + (r[s.key]||0); }, 0); };
    var max = rows.reduce(function(a, r){ return Math.max(a, total(r)); }, 0);

    var plot = document.createElement('div');
    plot.className = 'viz-plot';
    host.appendChild(plot);

    if(!rows.length || max <= 0){
      plot.innerHTML = '<div class="viz-empty">Aucune activité sur la période.</div>';
    } else {
      var tip = document.createElement('div');
      tip.className = 'viz-tip'; tip.setAttribute('role','status');
      plot.appendChild(tip);
      draw();
      if(window.ResizeObserver){
        var lastW = plot.clientWidth;
        new ResizeObserver(function(){ if(Math.abs(plot.clientWidth - lastW) > 4){ lastW = plot.clientWidth; draw(); } }).observe(plot);
      }
    }

    function draw(){
      var old = plot.querySelector('svg'); if(old) old.remove();
      var W = Math.max(280, plot.clientWidth || 600), H = 240, m = { l:52, r:8, t:10, b:26 };
      var iw = W - m.l - m.r, ih = H - m.t - m.b;
      var ticks = Elikya.stats.niceTicks(max, 4);
      var y = function(v){ return m.t + ih - v / ticks.max * ih; };
      var band = iw / rows.length, bw = Math.max(3, Math.min(24, band * 0.62));
      var svg = el('svg', { viewBox:'0 0 '+W+' '+H, width:'100%', height:H, role:'img',
        'aria-label': opts.label || 'Graphique' });

      // grille + graduations
      ticks.ticks.forEach(function(t){
        svg.appendChild(el('line', { x1:m.l, x2:W-m.r, y1:y(t), y2:y(t), class: t === 0 ? 'viz-base' : 'viz-grid' }));
        var lab = el('text', { x:m.l-8, y:y(t)+4, 'text-anchor':'end', class:'viz-axis' }); lab.textContent = compact(t);
        svg.appendChild(lab);
      });
      // étiquettes de jours : espacées d'au moins ~34 px
      var every = Math.max(1, Math.ceil(34 / band));
      rows.forEach(function(r, i){
        if(i % every && i !== rows.length - 1) return;
        var t = el('text', { x:m.l + band*i + band/2, y:H-8, 'text-anchor':'middle', class:'viz-axis' });
        t.textContent = String(+r.jour.slice(8));
        svg.appendChild(t);
      });

      var hover = el('rect', { y:m.t, width:band, height:ih, class:'viz-hover', opacity:0 });
      svg.appendChild(hover);

      rows.forEach(function(r, i){
        var x = m.l + band*i + (band - bw)/2, acc = 0;
        var nonZero = series.filter(function(s){ return (r[s.key]||0) > 0; });
        nonZero.forEach(function(s, j){
          var v = r[s.key], y0 = y(acc), y1 = y(acc + v), h = y0 - y1;
          var gap = j > 0 ? 2 : 0; // écart de 2 px (couleur de fond) entre segments
          if(h - gap <= 0.5){ acc += v; return; }
          var isTop = j === nonZero.length - 1;
          svg.appendChild(isTop
            ? el('path', { d: topRounded(x, y1, bw, h - gap, 4), fill:s.color })
            : el('rect', { x:x, y:y1, width:bw, height:h - gap, fill:s.color }));
          acc += v;
        });
        // zone de survol = toute la bande (plus large que la colonne)
        var hit = el('rect', { x:m.l + band*i, y:m.t, width:band, height:ih, fill:'transparent', tabindex:0,
          'aria-label': jourLong(r.jour)+' : '+fmt(total(r)) });
        hit.addEventListener('mouseenter', function(){ show(i, r); });
        hit.addEventListener('focus', function(){ show(i, r); });
        hit.addEventListener('mouseleave', hide);
        hit.addEventListener('blur', hide);
        svg.appendChild(hit);
      });
      plot.insertBefore(svg, tip);

      function show(i, r){
        hover.setAttribute('x', m.l + band*i); hover.setAttribute('opacity', 1);
        tip.innerHTML = '<b>'+esc(jourLong(r.jour))+'</b>'+
          series.map(function(s){ return '<div><i style="background:'+s.color+'"></i>'+esc(s.label)+'<span>'+esc(fmt(r[s.key]||0))+'</span></div>'; }).join('')+
          '<div class="tot">Total<span>'+esc(fmt(total(r)))+'</span></div>';
        tip.style.display = 'block';
        var cx = (m.l + band*i + band/2) / W * plot.clientWidth;
        var left = cx + 14, tw = tip.offsetWidth;
        if(left + tw > plot.clientWidth) left = cx - tw - 14;
        tip.style.left = Math.max(0, left)+'px';
        tip.style.top = '8px';
      }
      function hide(){ hover.setAttribute('opacity', 0); tip.style.display = 'none'; }
    }

    // tableau des valeurs (accessibilité / lecture précise)
    var det = document.createElement('details');
    det.className = 'viz-table';
    det.innerHTML = '<summary>Voir les valeurs en tableau</summary><div class="table-wrap"><table><thead><tr><th>Jour</th>'+
      series.map(function(s){ return '<th class="num">'+esc(s.label)+'</th>'; }).join('')+'<th class="num">Total</th></tr></thead><tbody>'+
      rows.map(function(r){ return '<tr><td>'+esc(jourLong(r.jour))+'</td>'+
        series.map(function(s){ return '<td class="num tnum">'+esc(fmt(r[s.key]||0))+'</td>'; }).join('')+
        '<td class="num tnum"><b>'+esc(fmt(total(r)))+'</b></td></tr>'; }).join('')+
      '</tbody></table></div>';
    host.appendChild(det);
  }

  Elikya.charts = { stackedColumns: stackedColumns };
})();
