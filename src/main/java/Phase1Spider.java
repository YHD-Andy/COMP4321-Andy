import jdbm.RecordManager;
import jdbm.RecordManagerFactory;
import jdbm.htree.HTree;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.Serializable;
import java.net.URI;
import java.net.URL;
import java.net.URLConnection;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Queue;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

class PostingData implements Serializable {
    public int freq;
    public ArrayList<Integer> positions;

    PostingData(int freq, ArrayList<Integer> positions) {
        this.freq = freq;
        this.positions = positions;
    }
}

class PageInfo implements Serializable {
    public int pageId;
    public String url;
    public String title;
    public long lastModified;
    public int size;
    public HashMap<String, Integer> bodyFreq;
    public HashMap<String, ArrayList<Integer>> bodyPositions;
    public HashMap<String, ArrayList<Integer>> titlePositions;

    PageInfo() {
        bodyFreq = new HashMap<String, Integer>();
        bodyPositions = new HashMap<String, ArrayList<Integer>>();
        titlePositions = new HashMap<String, ArrayList<Integer>>();
    }
}

class CrawledPage {
    public String title;
    public String bodyText;
    public long lastModified;
    public int size;
    public ArrayList<String> links;
}

public class Phase1Spider {
    private static final Pattern TOKEN_PATTERN = Pattern.compile("[A-Za-z0-9]+");
    private static final Pattern HREF_PATTERN = Pattern.compile("(?i)<a[^>]+href\\s*=\\s*[\"']([^\"'#]+)[\"']");
    private static final Pattern TITLE_PATTERN = Pattern.compile("(?is)<title>(.*?)</title>");

    private final RecordManager recman;
    private final HTree urlToId;
    private final HTree idToUrl;
    private final HTree pageMeta;
    private final HTree bodyIndex;
    private final HTree titleIndex;
    private final HTree parentToChildren;
    private final HTree childToParents;
    private final HTree metadata;
    private final StopStem stopStem;
    private int nextPageId;

    private Phase1Spider(String dbBasePath, String stopwordPath) throws IOException {
        recman = RecordManagerFactory.createRecordManager(dbBasePath);
        urlToId = openOrCreateHTree("urlToId");
        idToUrl = openOrCreateHTree("idToUrl");
        pageMeta = openOrCreateHTree("pageMeta");
        bodyIndex = openOrCreateHTree("bodyIndex");
        titleIndex = openOrCreateHTree("titleIndex");
        parentToChildren = openOrCreateHTree("parentToChildren");
        childToParents = openOrCreateHTree("childToParents");
        metadata = openOrCreateHTree("metadata");
        stopStem = new StopStem(stopwordPath);
        Integer persistedNext = (Integer) metadata.get("nextPageId");
        nextPageId = (persistedNext == null) ? 1 : persistedNext.intValue();
    }

    private HTree openOrCreateHTree(String name) throws IOException {
        long recid = recman.getNamedObject(name);
        if (recid != 0) {
            return HTree.load(recman, recid);
        }
        HTree table = HTree.createInstance(recman);
        recman.setNamedObject(name, table.getRecid());
        return table;
    }

    private void close() throws IOException {
        metadata.put("nextPageId", Integer.valueOf(nextPageId));
        recman.commit();
        recman.close();
    }

    private String normalizeUrl(String baseUrl, String link) {
        try {
            URL resolved = new URL(new URL(baseUrl), link);
            URI uri = resolved.toURI().normalize();
            URI noFragment = new URI(
                    uri.getScheme(),
                    uri.getUserInfo(),
                    uri.getHost(),
                    uri.getPort(),
                    uri.getPath(),
                    uri.getQuery(),
                    null
            );
            return noFragment.toString();
        } catch (Exception ex) {
            return null;
        }
    }

    private String normalizeAbsoluteUrl(String url) {
        try {
            return normalizeUrl(url, url);
        } catch (Exception ex) {
            return null;
        }
    }

    private boolean sameHost(String seedHost, String targetUrl) {
        try {
            URL url = new URL(targetUrl);
            return seedHost.equalsIgnoreCase(url.getHost());
        } catch (Exception ex) {
            return false;
        }
    }

    private int ensurePageId(String normalizedUrl) throws IOException {
        Integer id = (Integer) urlToId.get(normalizedUrl);
        if (id != null) {
            return id.intValue();
        }
        int assigned = nextPageId++;
        urlToId.put(normalizedUrl, Integer.valueOf(assigned));
        idToUrl.put(Integer.valueOf(assigned), normalizedUrl);
        return assigned;
    }

    private long readRemoteLastModified(String normalizedUrl) {
        try {
            URLConnection connection = new URL(normalizedUrl).openConnection();
            connection.setConnectTimeout(10000);
            connection.setReadTimeout(10000);
            long lastModified = connection.getLastModified();
            if (lastModified <= 0) {
                lastModified = connection.getDate();
            }
            return lastModified;
        } catch (Exception ex) {
            return -1L;
        }
    }

    private boolean shouldFetch(String normalizedUrl, int pageId) throws IOException {
        PageInfo old = (PageInfo) pageMeta.get(Integer.valueOf(pageId));
        if (old == null) {
            return true;
        }
        long remoteLastModified = readRemoteLastModified(normalizedUrl);
        if (remoteLastModified <= 0) {
            return false;
        }
        return remoteLastModified > old.lastModified;
    }

    private CrawledPage fetchPage(String normalizedUrl) {
        try {
            URLConnection connection = new URL(normalizedUrl).openConnection();
            connection.setConnectTimeout(10000);
            connection.setReadTimeout(10000);
            connection.setRequestProperty("User-Agent", "COMP4321-Phase1-Spider/1.0");

            StringBuilder htmlBuilder = new StringBuilder();
            BufferedReader reader = new BufferedReader(
                    new InputStreamReader(connection.getInputStream(), StandardCharsets.UTF_8)
            );
            try {
                String line;
                while ((line = reader.readLine()) != null) {
                    htmlBuilder.append(line).append('\n');
                }
            } finally {
                reader.close();
            }
            String html = htmlBuilder.toString();

            String bodyText = html
                    .replaceAll("(?is)<script.*?>.*?</script>", " ")
                    .replaceAll("(?is)<style.*?>.*?</style>", " ")
                    .replaceAll("(?is)<[^>]+>", " ")
                    .replaceAll("&nbsp;", " ");

            ArrayList<String> linkList = new ArrayList<String>();
            Matcher linkMatcher = HREF_PATTERN.matcher(html);
            while (linkMatcher.find()) {
                linkList.add(linkMatcher.group(1));
            }

            String title = normalizedUrl;
            Matcher titleMatcher = TITLE_PATTERN.matcher(html);
            if (titleMatcher.find()) {
                String extractedTitle = titleMatcher.group(1).replaceAll("(?is)<[^>]+>", " ").trim();
                if (extractedTitle.length() > 0) {
                    title = extractedTitle;
                }
            }

            long lastModified = connection.getLastModified();
            if (lastModified <= 0) {
                lastModified = connection.getDate();
            }
            if (lastModified <= 0) {
                lastModified = System.currentTimeMillis();
            }

            long length = connection.getContentLengthLong();
            int size;
            if (length > 0) {
                size = (int) Math.min(Integer.MAX_VALUE, length);
            } else {
                size = html.length();
            }

            CrawledPage page = new CrawledPage();
            page.title = title;
            page.bodyText = bodyText;
            page.lastModified = lastModified;
            page.size = size;
            page.links = linkList;
            return page;
        } catch (Exception ex) {
            System.err.println("Failed to fetch page: " + normalizedUrl + " - " + ex.toString());
            return null;
        }
    }

    private HashMap<String, ArrayList<Integer>> tokenizeAndStemWithPositions(String text) {
        HashMap<String, ArrayList<Integer>> map = new HashMap<String, ArrayList<Integer>>();
        Matcher matcher = TOKEN_PATTERN.matcher(text == null ? "" : text);
        int position = 0;
        while (matcher.find()) {
            String token = matcher.group().toLowerCase(Locale.ENGLISH);
            if (stopStem.isStopWord(token)) {
                continue;
            }
            String stem = stopStem.stem(token);
            if (stem == null || stem.length() == 0) {
                continue;
            }
            ArrayList<Integer> positions = map.get(stem);
            if (positions == null) {
                positions = new ArrayList<Integer>();
                map.put(stem, positions);
            }
            positions.add(Integer.valueOf(position));
            position++;
        }
        return map;
    }

    private HashMap<String, Integer> toFreqMap(HashMap<String, ArrayList<Integer>> positions) {
        HashMap<String, Integer> freq = new HashMap<String, Integer>();
        for (Map.Entry<String, ArrayList<Integer>> entry : positions.entrySet()) {
            freq.put(entry.getKey(), Integer.valueOf(entry.getValue().size()));
        }
        return freq;
    }

    @SuppressWarnings("unchecked")
    private void addToIndex(HTree index, int docId, HashMap<String, ArrayList<Integer>> termPositions) throws IOException {
        for (Map.Entry<String, ArrayList<Integer>> entry : termPositions.entrySet()) {
            String term = entry.getKey();
            ArrayList<Integer> positions = entry.getValue();
            HashMap<Integer, PostingData> postingList = (HashMap<Integer, PostingData>) index.get(term);
            if (postingList == null) {
                postingList = new HashMap<Integer, PostingData>();
            }
            postingList.put(Integer.valueOf(docId), new PostingData(positions.size(), new ArrayList<Integer>(positions)));
            index.put(term, postingList);
        }
    }

    @SuppressWarnings("unchecked")
    private void removeFromIndex(HTree index, int docId, HashMap<String, ArrayList<Integer>> termPositions) throws IOException {
        for (Map.Entry<String, ArrayList<Integer>> entry : termPositions.entrySet()) {
            String term = entry.getKey();
            HashMap<Integer, PostingData> postingList = (HashMap<Integer, PostingData>) index.get(term);
            if (postingList == null) {
                continue;
            }
            postingList.remove(Integer.valueOf(docId));
            if (postingList.isEmpty()) {
                index.remove(term);
            } else {
                index.put(term, postingList);
            }
        }
    }

    @SuppressWarnings("unchecked")
    private void addDirectedEdge(HTree graph, int from, int to) throws IOException {
        HashSet<Integer> out = (HashSet<Integer>) graph.get(Integer.valueOf(from));
        if (out == null) {
            out = new HashSet<Integer>();
        }
        out.add(Integer.valueOf(to));
        graph.put(Integer.valueOf(from), out);
    }

    private void addLinkRelation(int parentId, int childId) throws IOException {
        addDirectedEdge(parentToChildren, parentId, childId);
        addDirectedEdge(childToParents, childId, parentId);
    }

    @SuppressWarnings("unchecked")
    private void enqueueStoredChildren(int parentId, HashSet<String> discovered, Queue<String> queue) throws IOException {
        HashSet<Integer> children = (HashSet<Integer>) parentToChildren.get(Integer.valueOf(parentId));
        if (children == null) {
            return;
        }
        for (Integer childId : children) {
            String childUrl = (String) idToUrl.get(childId);
            if (childUrl == null) {
                continue;
            }
            if (!discovered.contains(childUrl)) {
                discovered.add(childUrl);
                queue.offer(childUrl);
            }
        }
    }

    private PageInfo buildPageInfo(int pageId, String normalizedUrl, CrawledPage page) {
        PageInfo info = new PageInfo();
        info.pageId = pageId;
        info.url = normalizedUrl;
        info.title = page.title;
        info.lastModified = page.lastModified;
        info.size = page.size;
        info.bodyPositions = tokenizeAndStemWithPositions(page.bodyText);
        info.bodyFreq = toFreqMap(info.bodyPositions);
        info.titlePositions = tokenizeAndStemWithPositions(page.title);
        return info;
    }

    private void crawl(String startUrl, int maxPages) throws IOException {
        String normalizedStart = normalizeAbsoluteUrl(startUrl);
        if (normalizedStart == null) {
            throw new IOException("Invalid start URL: " + startUrl);
        }

        String seedHost;
        try {
            seedHost = new URL(normalizedStart).getHost();
        } catch (Exception ex) {
            throw new IOException("Failed to parse seed host: " + normalizedStart);
        }

        Queue<String> queue = new ArrayDeque<String>();
        HashSet<String> discovered = new HashSet<String>();
        queue.offer(normalizedStart);
        discovered.add(normalizedStart);

        int fetched = 0;
        while (!queue.isEmpty() && fetched < maxPages) {
            String currentUrl = queue.poll();
            int parentId = ensurePageId(currentUrl);

            if (!shouldFetch(currentUrl, parentId)) {
                enqueueStoredChildren(parentId, discovered, queue);
                continue;
            }

            CrawledPage page = fetchPage(currentUrl);
            if (page == null) {
                continue;
            }

            PageInfo oldInfo = (PageInfo) pageMeta.get(Integer.valueOf(parentId));
            if (oldInfo != null) {
                removeFromIndex(bodyIndex, parentId, oldInfo.bodyPositions);
                removeFromIndex(titleIndex, parentId, oldInfo.titlePositions);
            }

            PageInfo newInfo = buildPageInfo(parentId, currentUrl, page);
            pageMeta.put(Integer.valueOf(parentId), newInfo);
            addToIndex(bodyIndex, parentId, newInfo.bodyPositions);
            addToIndex(titleIndex, parentId, newInfo.titlePositions);

            for (int i = 0; i < page.links.size(); i++) {
                String normalizedChild = normalizeUrl(currentUrl, page.links.get(i));
                if (normalizedChild == null) {
                    continue;
                }
                if (!sameHost(seedHost, normalizedChild)) {
                    continue;
                }
                int childId = ensurePageId(normalizedChild);
                addLinkRelation(parentId, childId);
                if (!discovered.contains(normalizedChild)) {
                    discovered.add(normalizedChild);
                    queue.offer(normalizedChild);
                }
            }

            fetched++;
            recman.commit();
            System.out.println("Fetched page " + fetched + "/" + maxPages + ": " + currentUrl);
        }

        metadata.put("nextPageId", Integer.valueOf(nextPageId));
        recman.commit();
        System.out.println("Crawl completed. Fetched pages: " + fetched);
        System.out.println("Last crawl timestamp: " + new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ENGLISH).format(new Date()));
    }

    public static void main(String[] args) {
        String startUrl = "https://www.cse.ust.hk/~kwtleung/COMP4321/testpage.htm";
        int pages = 30;
        String dbBasePath = "db/phase1";
        String stopwordPath = "src/main/resource/stopwords.txt";

        if (args.length >= 1) {
            startUrl = args[0];
        }
        if (args.length >= 2) {
            pages = Integer.parseInt(args[1]);
        }
        if (args.length >= 3) {
            dbBasePath = args[2];
        }
        if (args.length >= 4) {
            stopwordPath = args[3];
        }

        Phase1Spider spider = null;
        try {
            spider = new Phase1Spider(dbBasePath, stopwordPath);
            spider.crawl(startUrl, pages);
        } catch (Exception ex) {
            System.err.println("Spider failed: " + ex.toString());
            ex.printStackTrace();
        } finally {
            if (spider != null) {
                try {
                    spider.close();
                } catch (IOException ignored) {
                }
            }
        }
    }
}
