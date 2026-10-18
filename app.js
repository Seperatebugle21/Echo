'use strict';
document.querySelector('#year').textContent=String(new Date().getFullYear());
// Keep the verified release as a usable fallback if GitHub is unavailable.
async function refreshRelease(){
  try{
    const response=await fetch('https://api.github.com/repos/Seperatebugle21/Echo/releases/latest',{headers:{Accept:'application/vnd.github+json'},signal:AbortSignal.timeout(6000)});
    if(!response.ok)return;const release=await response.json();
    if(release.draft||release.prerelease)return;
    const asset=release.assets?.find(a=>a.name.toLowerCase().endsWith('.ipa')&&a.state==='uploaded');
    if(!asset)return;
    const url=new URL(asset.browser_download_url);
    if(url.origin!=='https://github.com'||!url.pathname.startsWith('/Seperatebugle21/Echo/releases/download/'))return;
    document.querySelectorAll('[data-download]').forEach(a=>a.href=url.href);
    document.querySelector('[data-release-pill]').textContent=`Echo ${release.tag_name} is here`;
    document.querySelector('[data-release-label]').textContent=`${release.tag_name} · Available on GitHub`;
    document.querySelector('[data-size]').textContent=`${(asset.size/1000000).toLocaleString('en-GB',{maximumFractionDigits:1})} MB`;
  }catch{/* The verified v1.0 download stays available without the API. */}
}
refreshRelease();
