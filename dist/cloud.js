(() => {
  'use strict';
  const cfg = window.CARD_APP_CONFIG || {};
  const url = String(cfg.supabaseUrl || '').trim();
  const anonKey = String(cfg.supabaseAnonKey || '').trim();
  const api = window.supabase;
  const configured = Boolean(url && anonKey && api?.createClient);
  const client = configured ? api.createClient(url, anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  }) : null;
  let user = null;
  let admin = false;
  let catalogSnapshot = { productIds: [], cardIds: [] };
  let banlistSnapshot = [];

  const fail = (error) => { if (error) throw new Error(error.message || String(error)); };
  const required = () => {
    if (!client) throw new Error('ยังไม่ได้ตั้งค่า Supabase URL / anon key');
    if (!user) throw new Error('กรุณาเข้าสู่ระบบก่อน');
    return client;
  };
  const chunks = (items, size = 400) => Array.from({ length: Math.ceil(items.length / size) }, (_, i) => items.slice(i * size, (i + 1) * size));
  const cleanNumber = (value) => value === '' || value == null || !Number.isFinite(Number(value)) ? null : Number(value);
  const CARD_FIELDS = new Set(['id','no','name','description','race','clan','icon','nation','nation2','unit','grade','power','shield','rarity','trigger','img','fit','orient','pid','pname','collectionCount','is_gacha_pool']);

  async function rows(table, query) {
    const { data, error } = await query;
    fail(error);
    return data || [];
  }

  function cardFromRow(row, productNo) {
    return {
      ...(row.attributes || {}),
      id: row.id,
      no: productNo || row.card_no || '',
      name: row.name || '',
      description: row.description || '',
      race: row.race || '',
      clan: row.clan || '',
      icon: row.icon || '',
      nation: row.nation || '',
      nation2: row.second_nation || '',
      unit: row.card_type || '',
      grade: row.grade == null ? '' : String(row.grade),
      power: row.power == null ? '' : String(row.power),
      shield: row.shield == null ? '' : String(row.shield),
      rarity: row.rarity || 'C',
      trigger: row.trigger_type || '',
      img: row.image_url || '',
      fit: row.image_fit || null,
      orient: row.orientation || undefined,
      is_gacha_pool: row.is_gacha_pool !== false,
      lastEditedBy: row.updated_by || '',
      lastEditedAt: row.updated_at || '',
      lastEditedByName: row.updated_by_name || '',
    };
  }

  function cardToRow(card) {
    const attributes = Object.fromEntries(Object.entries(card || {}).filter(([key]) => !CARD_FIELDS.has(key)));
    return {
      id: card.id,
      card_no: String(card.no || ''),
      name: String(card.name || ''),
      description: String(card.description || ''),
      race: card.race ?? '',
      clan: card.clan ?? '',
      icon: card.icon ?? '',
      nation: card.nation || null,
      second_nation: card.nation2 || null,
      card_type: card.unit || null,
      grade: cleanNumber(card.grade),
      power: cleanNumber(card.power),
      shield: cleanNumber(card.shield),
      rarity: String(card.rarity || 'C'),
      trigger_type: card.trigger || null,
      image_url: card.img || null,
      image_fit: card.fit || null,
      orientation: card.orient || null,
      attributes,
      is_gacha_pool: card.is_gacha_pool !== false,
      updated_by: user.id,
      updated_at: new Date().toISOString(),
      deleted_at: null,
    };
  }

  function productFromRow(row, cards) {
    const fit = row.cover_fit || {};
    return {
      id: row.id,
      year: row.release_year || new Date().getFullYear(),
      type: row.product_type || 'Others',
      name: row.name || '',
      cover: row.cover_url || '',
      fit: fit.fit || null,
      packMode: fit.packMode || 'auto',
      packW: fit.packW ?? 82,
      packH: fit.packH ?? 92,
      packX: fit.packX ?? 50,
      packY: fit.packY ?? 50,
      packCover: fit.packCover || '',
      includeAllProducts: fit.includeAllProducts !== false,
      gachaWeights: row.gacha_weights || {},
      cards,
    };
  }

  async function refreshAdmin() {
    admin = false;
    if (!user) return false;
    const { data, error } = await client.from('profiles').select('is_admin').eq('id', user.id).maybeSingle();
    if (error) { console.warn('Admin flag is not available yet; treating user as non-admin.', error.message); admin = false; return false; }
    admin = data?.is_admin === true;
    return admin;
  }
  async function init() {
    if (!configured) return { configured: false, user: null, admin: false };
    const { data, error } = await client.auth.getSession();
    fail(error);
    user = data.session?.user || null;
    await refreshAdmin();
    client.auth.onAuthStateChange((_event, session) => {
      user = session?.user || null;
      refreshAdmin().finally(() => window.dispatchEvent(new CustomEvent('cardcloud:auth', { detail: { user, admin } })));
    });
    return { configured: true, user, admin };
  }

  async function signIn(email, password) {
    if (!client) throw new Error('ยังไม่ได้ตั้งค่า Supabase URL / anon key');
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    fail(error); user = data.user || data.session?.user || null; await refreshAdmin();
    return data;
  }
  async function signUp(email, password, displayName) {
    if (!client) throw new Error('ยังไม่ได้ตั้งค่า Supabase URL / anon key');
    const { data, error } = await client.auth.signUp({
      email, password, options: { data: { display_name: displayName || 'Player' } },
    });
    fail(error); user = data.user && data.session ? data.user : user; if (user) await refreshAdmin();
    return data;
  }
  async function signOut() { required(); const { error } = await client.auth.signOut(); fail(error); user = null; admin = false; }

  async function loadCatalog() {
    required();
    const [products, cards, links] = await Promise.all([
      rows('catalog_products', client.from('catalog_products').select('*').is('deleted_at', null).order('release_year', { ascending: false }).range(0, 9999)),
      rows('catalog_cards', client.from('catalog_cards').select('*').is('deleted_at', null).range(0, 9999)),
      rows('product_cards', client.from('product_cards').select('product_id,card_id,product_card_no').range(0, 9999)),
    ]);
    const byCard = new Map(cards.map((card) => [card.id, card]));
    const byProduct = new Map(products.map((product) => [product.id, []]));
    for (const link of links) {
      const list = byProduct.get(link.product_id);
      const card = byCard.get(link.card_id);
      if (list && card) list.push(cardFromRow(card, link.product_card_no));
    }
    catalogSnapshot = { productIds: products.map((x) => x.id), cardIds: cards.map((x) => x.id) };
    const editorIds = [...new Set([...products, ...cards].map((x) => x.updated_by).filter(Boolean))];
    const editors = editorIds.length ? await rows('profiles', client.from('profiles').select('id,display_name').in('id', editorIds)) : [];
    const editorNames = new Map(editors.map((x) => [x.id, x.display_name || 'ผู้ใช้']));
    cards.forEach((x) => { x.updated_by_name = editorNames.get(x.updated_by) || ''; });
    products.forEach((x) => { x.updated_by_name = editorNames.get(x.updated_by) || ''; });
    return products.map((row) => productFromRow(row, byProduct.get(row.id) || []));
  }

  async function loadAppSettings() {
    required();
    const { data, error } = await client.from('app_settings').select('setting_value').eq('setting_key', 'catalog_ui').maybeSingle();
    fail(error);
    return data?.setting_value || null;
  }

  async function saveAppSettings(settings) {
    required();
    const { error } = await client.from('app_settings').upsert({
      setting_key: 'catalog_ui', setting_value: settings || {}, updated_by: user.id, updated_at: new Date().toISOString(),
    }, { onConflict: 'setting_key' });
    fail(error);
  }

  async function saveCatalog(db, options = {}) {
    required();
    let catalogCoreSaved = false;
    const saveFail = (error) => {
      if (!error) return;
      const out = new Error(error.message || String(error));
      if (catalogCoreSaved) out.catalogSaved = true;
      throw out;
    };
    const uploadedImages = new Map();
    const publicImage = async (value, name) => {
      if (!String(value || '').startsWith('data:image/')) return value || null;
      if (!uploadedImages.has(value)) uploadedImages.set(value, await uploadDataUri(value, name));
      return uploadedImages.get(value);
    };
    for (const product of db.products || []) {
      product.cover = await publicImage(product.cover, `${product.id}-pack`);
      product.packCover = await publicImage(product.packCover, `${product.id}-pack-cover`);
      for (const card of product.cards || []) card.img = await publicImage(card.img, `${card.id}-card`);
    }
    // Save shared UI settings, including the aggregate pack cover, so every
    // signed-in user receives the same image instead of a browser-local copy.
    if (db.settings) {
      const settings = { ...db.settings, allProductsCover: await publicImage(db.settings.allProductsCover, 'all-products-pack') };
      await saveAppSettings(settings);
    }
    const products = (db.products || []).map((p) => ({
      id: p.id,
      name: String(p.name || ''),
      product_type: p.type || 'Others',
      release_year: cleanNumber(p.year),
      cover_url: p.cover || null,
      cover_fit: { fit: p.fit || null, packMode: p.packMode || 'auto', packW: p.packW ?? 82, packH: p.packH ?? 92, packX: p.packX ?? 50, packY: p.packY ?? 50, packCover: p.packCover || '', includeAllProducts: p.includeAllProducts !== false },
      gacha_weights: p.gachaWeights || {},
      updated_by: user.id,
      updated_at: new Date().toISOString(),
      deleted_at: null,
    }));
    const allCards = new Map();
    const links = [];
    for (const product of (db.products || [])) {
      for (const card of (product.cards || [])) {
        allCards.set(card.id, cardToRow(card));
        links.push({ product_id: product.id, card_id: card.id, product_card_no: String(card.no || '') || null });
      }
    }
    for (const batch of chunks(products)) { const { error } = await client.from('catalog_products').upsert(batch, { onConflict: 'id' }); saveFail(error); }
    if (!options.skipCards) {
      for (const batch of chunks([...allCards.values()])) { const { error } = await client.from('catalog_cards').upsert(batch, { onConflict: 'id' }); saveFail(error); }
    }
    // The product/card rows are the user-visible catalog data. Later link and
    // cleanup operations should not turn a committed card edit into a false failure.
    catalogCoreSaved = true;

    const currentProductIds = products.map((x) => x.id);
    if (options.skipCards) {
      catalogSnapshot = { productIds: currentProductIds, cardIds: catalogSnapshot.cardIds };
      return;
    }
    for (const productId of currentProductIds) {
      const currentCards = links.filter((x) => x.product_id === productId).map((x) => x.card_id);
      const existing = await rows('product_cards', client.from('product_cards').select('card_id').eq('product_id', productId));
      const removedLinks = existing.map((x) => x.card_id).filter((id) => !currentCards.includes(id));
      if (removedLinks.length) { const { error } = await client.from('product_cards').delete().eq('product_id', productId).in('card_id', removedLinks); saveFail(error); }
    }
    const removedProducts = catalogSnapshot.productIds.filter((id) => !currentProductIds.includes(id));
    for (const productId of removedProducts) { const { error } = await client.from('product_cards').delete().eq('product_id', productId); saveFail(error); }
    for (const batch of chunks(links)) { const { error } = await client.from('product_cards').upsert(batch, { onConflict: 'product_id,card_id' }); saveFail(error); }


    if (removedProducts.length) {
      const { error } = await client.from('catalog_products').update({ deleted_at: new Date().toISOString() }).in('id', removedProducts);
      saveFail(error);
    }
    const currentCardIds = [...allCards.keys()];
    const removedCards = catalogSnapshot.cardIds.filter((id) => !currentCardIds.includes(id));
    if (removedCards.length) {
      // Keep rows referenced by decks/recipes/collection; soft deletion is reversible.
      const { error } = await client.from('catalog_cards').update({ deleted_at: new Date().toISOString() }).in('id', removedCards);
      saveFail(error);
    }
    catalogSnapshot = { productIds: currentProductIds, cardIds: currentCardIds };
  }

  function subscribeCatalog(onChange) {
    if (!client || !user) return null;
    const channel = client.channel('catalog-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'catalog_products' }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'catalog_cards' }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'product_cards' }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'app_settings', filter: 'setting_key=eq.catalog_ui' }, onChange)
      .subscribe();
    return () => { client.removeChannel(channel); };
  }
  async function loadBanlist() {
    required();
    const rules = await rows('banlist_rules', client.from('banlist_rules').select('*').is('deleted_at', null).range(0, 9999));
    const cards = await rows('banlist_rule_cards', client.from('banlist_rule_cards').select('*').is('deleted_at', null).range(0, 9999));
    const activeRuleIds = new Set(rules.map((r) => r.id));
    const links = cards.filter((x) => activeRuleIds.has(x.rule_id));
    banlistSnapshot = rules.map((r) => r.id);
    return links.map((link) => {
      const r = rules.find((row) => row.id === link.rule_id);
      return { id: r.id, cardId: link.card_id, name: r.label || '', type: r.rule_type,
        zoneId: r.zone_key || '', limit: r.max_copies || 0, group: r.label || 'กลุ่ม 1' };
    });
  }

  async function saveBanlist(list) {
    required();
    const now = new Date().toISOString();
    const currentIds = list.map((r) => r.id);
    const ruleRows = list.map((r) => ({
      id: r.id,
      rule_type: r.type,
      label: r.type === 'together' ? (r.group || 'กลุ่ม 1') : (r.name || ''),
      zone_key: r.type === 'zone' ? (r.zoneId || 'main') : null,
      max_copies: r.type === 'limit' ? Math.max(1, Number.parseInt(r.limit, 10) || 1) : null,
      deleted_at: null,
      updated_at: now,
    }));
    for (const batch of chunks(ruleRows)) { const { error } = await client.from('banlist_rules').upsert(batch); fail(error); }
    const linkRows = list.map((r) => ({ rule_id: r.id, card_id: r.cardId, deleted_at: null }));
    for (const batch of chunks(linkRows)) { const { error } = await client.from('banlist_rule_cards').upsert(batch, { onConflict: 'rule_id,card_id' }); fail(error); }
    const removed = banlistSnapshot.filter((id) => !currentIds.includes(id));
    if (removed.length) {
      const { error: a } = await client.from('banlist_rules').update({ deleted_at: now, updated_at: now }).in('id', removed); fail(a);
      const { error: b } = await client.from('banlist_rule_cards').update({ deleted_at: now }).in('rule_id', removed); fail(b);
    }
    banlistSnapshot = currentIds;
  }

  async function loadFavourites() {
    required();
    return (await rows('user_favorite_cards', client.from('user_favorite_cards').select('card_id').eq('user_id', user.id).range(0, 9999))).map((row) => row.card_id);
  }
  async function setFavourite(cardId, enabled) {
    required();
    if (enabled) {
      const { error } = await client.from('user_favorite_cards').upsert({ user_id: user.id, card_id: cardId }, { onConflict: 'user_id,card_id' });
      fail(error);
    } else {
      const { error } = await client.from('user_favorite_cards').delete().eq('user_id', user.id).eq('card_id', cardId);
      fail(error);
    }
  }
  async function loadCollection() {
    required();
    const inventory = await rows('user_collection_cards', client.from('user_collection_cards').select('card_id,quantity').eq('user_id', user.id).range(0, 9999));
    const cardIds = inventory.map((x) => x.card_id);
    // Do not send every collected card id in one `in (...)` request. A large
    // collection can produce an oversized URL and browsers report that as the
    // unhelpful generic `TypeError: Failed to fetch`. Chunking also keeps the
    // post-gacha refresh reliable as the collection grows.
    const cards = cardIds.length
      ? (await Promise.all(chunks(cardIds, 200).map((ids) => rows(
          'catalog_cards',
          client.from('catalog_cards').select('*').in('id', ids).range(0, 9999),
        )))).flat()
      : [];
    const byId = new Map(cards.map((x) => [x.id, cardFromRow(x)]));
    return Object.fromEntries(inventory.map((x) => [x.card_id, { id: x.card_id, card: byId.get(x.card_id) || { id: x.card_id, name: 'การ์ดที่ไม่อยู่ใน Card List' }, count: x.quantity, productName: '' }]));
  }

  async function loadGachaState() {
    required();
    const { data, error } = await client.from('user_gacha_state').select('pity_count,packs_opened,pity_reset_on_high').eq('user_id', user.id).maybeSingle();
    fail(error);
    return data || { pity_count: 0, packs_opened: 0, pity_reset_on_high: true };
  }
  async function setPityReset(enabled) {
    required();
    const { error } = await client.rpc('set_gacha_pity_reset', { p_enabled: Boolean(enabled) }); fail(error);
  }
  async function resetPity() {
    required(); const { error } = await client.rpc('reset_gacha_pity'); fail(error);
  }
  async function recordPack(productId, cards) {
    required();
    const { data, error } = await client.rpc('record_pack_open', { p_product_id: productId, p_card_ids: cards.map((x) => x.id) });
    fail(error); return data;
  }
  async function recordMixedPack(cards, productIds) {
    required();
    const { data, error } = await client.rpc('record_mixed_pack_open', {
      p_card_ids: cards.map((x) => x.id),
      p_product_ids: productIds,
    });
    fail(error); return data;
  }
  async function loadDecks() {
    required();
    const decks = await rows('decks', client.from('decks').select('*').eq('owner_id', user.id).is('deleted_at', null).order('updated_at', { ascending: false }).range(0, 999));
    const ids = decks.map((d) => d.id);
    const cards = ids.length ? await rows('deck_cards', client.from('deck_cards').select('*').in('deck_id', ids).range(0, 9999)) : [];
    return Object.fromEntries(decks.map((d) => {
      const z = {};
      for (const row of cards.filter((x) => x.deck_id === d.id)) (z[row.zone_key] ||= {})[row.card_id] = row.quantity;
      return [d.name, { id: d.id, name: d.name, description: d.description || '', isShared: d.is_shared,
        z, names: {} }];
    }));
  }
  async function saveDeck(deck) {
    required();
    deck.id ||= crypto.randomUUID();
    const { error } = await client.from('decks').upsert({ id: deck.id, owner_id: user.id, name: deck.name,
      description: deck.description || '', is_shared: Boolean(deck.isShared), deleted_at: null, updated_at: new Date().toISOString() });
    fail(error);
    const { error: removeError } = await client.from('deck_cards').delete().eq('deck_id', deck.id); fail(removeError);
    const rowsToSave = Object.entries(deck.z || {}).flatMap(([zoneKey, values]) => Object.entries(values || {}).filter(([, quantity]) => quantity > 0).map(([cardId, quantity]) => ({ deck_id: deck.id, card_id: cardId, zone_key: zoneKey, quantity })));
    for (const batch of chunks(rowsToSave)) { const { error: writeError } = await client.from('deck_cards').upsert(batch); fail(writeError); }
  }
  async function deleteDeck(deckId) {
    required(); const { error } = await client.from('decks').delete().eq('id', deckId).eq('owner_id', user.id); fail(error);
  }
  async function loadSharedDecks() {
    required();
    const decks = await rows('decks', client.from('decks').select('id,owner_id,name,description,shared_at').eq('is_shared', true).is('deleted_at', null).order('shared_at', { ascending: false }).limit(50));
    const ownerIds = [...new Set(decks.map((d) => d.owner_id))];
    const profiles = ownerIds.length ? await rows('profiles', client.from('profiles').select('id,display_name').in('id', ownerIds)) : [];
    const byId = new Map(profiles.map((p) => [p.id, p.display_name]));
    return decks.map((d) => ({ ...d, owner_name: byId.get(d.owner_id) || 'Player' }));
  }
  async function copySharedDeck(deckId) {
    required();
    const decks = await rows('decks', client.from('decks').select('*').eq('id', deckId).eq('is_shared', true).limit(1));
    if (!decks[0]) throw new Error('ไม่พบเด็คที่แชร์');
    const cards = await rows('deck_cards', client.from('deck_cards').select('*').eq('deck_id', deckId));
    const z = {};
    for (const row of cards) (z[row.zone_key] ||= {})[row.card_id] = row.quantity;
    return { id: crypto.randomUUID(), name: `${decks[0].name} (copy)`, description: decks[0].description || '', isShared: false, z, names: {} };
  }

  async function loadRecipes() {
    required();
    const recipes = await rows('craft_recipes', client.from('craft_recipes').select('*').eq('is_active', true).order('created_at', { ascending: false }).range(0, 999));
    const ids = recipes.map((r) => r.id);
    const ingredients = ids.length ? await rows('craft_recipe_ingredients', client.from('craft_recipe_ingredients').select('*').in('recipe_id', ids)) : [];
    return recipes.map((recipe) => ({ ...recipe, ingredients: ingredients.filter((i) => i.recipe_id === recipe.id) }));
  }
  async function saveRecipe(recipe) {
    required();
    const id = recipe.id || crypto.randomUUID();
    const { error } = await client.from('craft_recipes').upsert({ id, title: recipe.title, description: recipe.description || '',
      target_card_id: recipe.target_card_id, output_quantity: Number(recipe.output_quantity) || 1,
      is_active: recipe.is_active !== false, created_by: user.id, updated_at: new Date().toISOString() });
    fail(error);
    const { error: delError } = await client.from('craft_recipe_ingredients').delete().eq('recipe_id', id); fail(delError);
    const ingredientRows = (recipe.ingredients || []).filter((x) => x.material_card_id && Number(x.quantity) > 0)
      .map((x) => ({ recipe_id: id, material_card_id: x.material_card_id, quantity: Number(x.quantity) }));
    for (const batch of chunks(ingredientRows)) { const { error: writeError } = await client.from('craft_recipe_ingredients').upsert(batch); fail(writeError); }
    return id;
  }
  async function craft(recipeId) {
    required(); const { data, error } = await client.rpc('craft_card', { p_recipe_id: recipeId }); fail(error); return data;
  }
  async function loadCraftHistory() {
    required();
    const history = await rows('craft_history', client.from('craft_history').select('id,recipe_title_snapshot,target_card_id,output_quantity,created_at').eq('user_id', user.id).order('created_at', { ascending: false }).limit(50));
    const ids = [...new Set(history.map((x) => x.target_card_id))];
    const cards = ids.length ? await rows('catalog_cards', client.from('catalog_cards').select('id,name,card_no,rarity').in('id', ids)) : [];
    const byId = new Map(cards.map((x) => [x.id, x]));
    return history.map((x) => ({ ...x, card: byId.get(x.target_card_id) || null }));
  }

  async function uploadDataUri(dataUri, originalName = 'card.jpg') {
    required();
    const match = String(dataUri).match(/^data:(image\/[\w.+-]+);base64,(.+)$/);
    if (!match) throw new Error('รูปภาพไม่อยู่ในรูปแบบที่รองรับ');
    const mime = match[1];
    const bytes = Uint8Array.from(atob(match[2]), (ch) => ch.charCodeAt(0));
    const ext = mime.split('/')[1].replace('jpeg', 'jpg');
    const path = `${user.id}/${crypto.randomUUID()}-${String(originalName).replace(/[^\w.-]/g, '_').slice(0, 60)}.${ext}`;
    const { error } = await client.storage.from('card-art').upload(path, new Blob([bytes], { type: mime }), { contentType: mime, upsert: false });
    fail(error);
    return client.storage.from('card-art').getPublicUrl(path).data.publicUrl;
  }

  window.CardCloud = Object.freeze({
    configured, get user() { return user; }, get admin() { return admin; }, client,
    init, signIn, signUp, signOut,
    loadCatalog, saveCatalog, loadAppSettings, saveAppSettings, subscribeCatalog, loadBanlist, saveBanlist, loadFavourites, setFavourite, loadCollection, loadGachaState,
    setPityReset, resetPity, recordPack, recordMixedPack,
    loadDecks, saveDeck, deleteDeck, loadSharedDecks, copySharedDeck,
    loadRecipes, saveRecipe, craft, loadCraftHistory, uploadDataUri,
  });
})();
