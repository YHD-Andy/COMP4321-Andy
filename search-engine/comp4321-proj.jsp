<%@ page import="jdbm.RecordManager" %>
<%@ page import="jdbm.RecordManagerFactory" %>
<%@ page import="jdbm.htree.HTree" %>
<%@ page import="jdbm.helper.FastIterator" %>
<%@ page import="java.io.File" %>
<%@ page import="java.lang.reflect.Constructor" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.text.DecimalFormat" %>
<%@ page import="java.text.SimpleDateFormat" %>
<%@ page import="java.util.ArrayList" %>
<%@ page import="java.util.Collections" %>
<%@ page import="java.util.Comparator" %>
<%@ page import="java.util.Date" %>
<%@ page import="java.util.HashMap" %>
<%@ page import="java.util.HashSet" %>
<%@ page import="java.util.LinkedHashMap" %>
<%@ page import="java.util.LinkedHashSet" %>
<%@ page import="java.util.List" %>
<%@ page import="java.util.Locale" %>
<%@ page import="java.util.Map" %>
<%@ page import="java.util.Set" %>
<%@ page import="java.util.regex.Matcher" %>
<%@ page import="java.util.regex.Pattern" %>
<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>

<%!
    private static final Pattern QUERY_PATTERN = Pattern.compile("\"([^\"]+)\"|(\\S+)");
    private static final Pattern TOKEN_PATTERN = Pattern.compile("[A-Za-z0-9]+");
    private static final double TITLE_BOOST = 3.0;
    private static final int MAX_RESULTS = 50;

    private static class ResultRow {
        int docId;
        double score;
        Object pageInfo;

        ResultRow(int docId, double score, Object pageInfo) {
            this.docId = docId;
            this.score = score;
            this.pageInfo = pageInfo;
        }
    }

    private Object getField(Object obj, String fieldName) {
        if (obj == null) {
            return null;
        }
        try {
            Field f = obj.getClass().getField(fieldName);
            return f.get(obj);
        } catch (Exception ex) {
            try {
                Field f = obj.getClass().getDeclaredField(fieldName);
                f.setAccessible(true);
                return f.get(obj);
            } catch (Exception ignored) {
                return null;
            }
        }
    }

    private String getStringField(Object obj, String fieldName) {
        Object v = getField(obj, fieldName);
        return v == null ? "" : String.valueOf(v);
    }

    private int getIntField(Object obj, String fieldName) {
        Object v = getField(obj, fieldName);
        if (v instanceof Integer) {
            return ((Integer) v).intValue();
        }
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        return 0;
    }

    private long getLongField(Object obj, String fieldName) {
        Object v = getField(obj, fieldName);
        if (v instanceof Long) {
            return ((Long) v).longValue();
        }
        if (v instanceof Number) {
            return ((Number) v).longValue();
        }
        return 0L;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Integer> getBodyFreqMap(Object pageInfo) {
        Object v = getField(pageInfo, "bodyFreq");
        return (v instanceof Map) ? (Map<String, Integer>) v : new HashMap<String, Integer>();
    }

    @SuppressWarnings("unchecked")
    private Map<String, List<Integer>> getPosMap(Object pageInfo, String fieldName) {
        Object v = getField(pageInfo, fieldName);
        return (v instanceof Map) ? (Map<String, List<Integer>>) v : new HashMap<String, List<Integer>>();
    }

    @SuppressWarnings("unchecked")
    private Map<Integer, Object> getPostingMap(HTree index, String term) throws Exception {
        Object v = index.get(term);
        return (v instanceof Map) ? (Map<Integer, Object>) v : new HashMap<Integer, Object>();
    }

    private int getPostingFreq(Object postingData) {
        Object v = getField(postingData, "freq");
        if (v instanceof Integer) {
            return ((Integer) v).intValue();
        }
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        return 0;
    }

    @SuppressWarnings("unchecked")
    private List<Integer> getPostingPositions(Object postingData) {
        Object v = getField(postingData, "positions");
        return (v instanceof List) ? (List<Integer>) v : new ArrayList<Integer>();
    }

    private Object createStopStem(String stopwordPath) {
        try {
            Class<?> cls = Class.forName("StopStem");
            Constructor<?> ctor = cls.getConstructor(String.class);
            return ctor.newInstance(stopwordPath);
        } catch (Exception ex) {
            try {
                ClassLoader cl = Thread.currentThread().getContextClassLoader();
                if (cl != null) {
                    Class<?> cls = Class.forName("StopStem", true, cl);
                    Constructor<?> ctor = cls.getConstructor(String.class);
                    return ctor.newInstance(stopwordPath);
                }
            } catch (Exception ignored) {
            }
            return null;
        }
    }

    private String heuristicStem(String token) {
        if (token == null) {
            return "";
        }
        String t = token;
        if (t.length() > 5 && t.endsWith("ing")) {
            return t.substring(0, t.length() - 3);
        }
        if (t.length() > 4 && t.endsWith("ed")) {
            return t.substring(0, t.length() - 2);
        }
        if (t.length() > 4 && t.endsWith("es")) {
            return t.substring(0, t.length() - 2);
        }
        if (t.length() > 4 && t.endsWith("er")) {
            return t.substring(0, t.length() - 2);
        }
        if (t.length() > 4 && t.endsWith("e")) {
            return t.substring(0, t.length() - 1);
        }
        if (t.length() > 3 && t.endsWith("s")) {
            return t.substring(0, t.length() - 1);
        }
        return t;
    }

    private int countDocsInDb(String dbBasePath) {
        RecordManager rm = null;
        try {
            if (dbBasePath == null || dbBasePath.trim().length() == 0) {
                return -1;
            }
            if (!new File(dbBasePath + ".db").exists()) {
                return -1;
            }
            rm = RecordManagerFactory.createRecordManager(dbBasePath);
            long pageMetaRecid = rm.getNamedObject("pageMeta");
            if (pageMetaRecid == 0L) {
                return 0;
            }
            HTree pageMetaTable = HTree.load(rm, pageMetaRecid);
            FastIterator it = pageMetaTable.keys();
            int count = 0;
            while (it.next() != null) {
                count++;
            }
            return count;
        } catch (Exception ex) {
            return -1;
        } finally {
            if (rm != null) {
                try {
                    rm.close();
                } catch (Exception ignored) {
                }
            }
        }
    }

    private String resolveDbBasePath(String appRoot, String configuredDbBasePath) {
        List<String> candidates = new ArrayList<String>();
        if (configuredDbBasePath != null && configuredDbBasePath.trim().length() > 0) {
            candidates.add(configuredDbBasePath.trim());
        }
        candidates.add(appRoot + File.separator + "WEB-INF" + File.separator + "db" + File.separator + "phase1");
        candidates.add(appRoot + File.separator + "WEB-INF" + File.separator + "db" + File.separator + "phase1_30");
        candidates.add(appRoot + File.separator + ".." + File.separator + "db" + File.separator + "phase1");
        candidates.add(appRoot + File.separator + ".." + File.separator + "db" + File.separator + "phase1_30");

        String bestPath = null;
        int bestCount = -1;
        for (String candidate : candidates) {
            int docCount = countDocsInDb(candidate);
            if (docCount > bestCount) {
                bestCount = docCount;
                bestPath = candidate;
            }
        }
        return bestPath;
    }

    private boolean isStopWord(Object stopStem, String token) {
        if (stopStem == null) {
            return false;
        }
        try {
            Object ret = stopStem.getClass().getMethod("isStopWord", String.class).invoke(stopStem, token);
            return (ret instanceof Boolean) && ((Boolean) ret).booleanValue();
        } catch (Exception ex) {
            return false;
        }
    }

    private String stem(Object stopStem, String token) {
        if (stopStem == null) {
            return token;
        }
        try {
            Object ret = stopStem.getClass().getMethod("stem", String.class).invoke(stopStem, token);
            return ret == null ? token : String.valueOf(ret);
        } catch (Exception ex) {
            return token;
        }
    }

    private List<String> normalizeAndStemTerms(Object stopStem, String text) {
        List<String> out = new ArrayList<String>();
        if (text == null) {
            return out;
        }
        Matcher m = TOKEN_PATTERN.matcher(text);
        while (m.find()) {
            String token = m.group().toLowerCase(Locale.ENGLISH);
            if (isStopWord(stopStem, token)) {
                continue;
            }
            String stemmed = stem(stopStem, token);
            if ((stemmed == null || stemmed.length() == 0 || stemmed.equals(token)) && stopStem == null) {
                stemmed = heuristicStem(token);
            }
            if (stemmed != null && stemmed.length() > 0) {
                out.add(stemmed);
            }
        }
        return out;
    }

    private boolean containsPhrase(Map<String, List<Integer>> posMap, List<String> phrase) {
        if (phrase == null || phrase.isEmpty()) {
            return true;
        }
        List<Integer> firstPositions = posMap.get(phrase.get(0));
        if (firstPositions == null || firstPositions.isEmpty()) {
            return false;
        }
        List<Set<Integer>> lookups = new ArrayList<Set<Integer>>();
        for (int i = 1; i < phrase.size(); i++) {
            List<Integer> p = posMap.get(phrase.get(i));
            if (p == null || p.isEmpty()) {
                return false;
            }
            lookups.add(new HashSet<Integer>(p));
        }
        for (Integer basePos : firstPositions) {
            boolean ok = true;
            for (int i = 1; i < phrase.size(); i++) {
                if (!lookups.get(i - 1).contains(Integer.valueOf(basePos.intValue() + i))) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                return true;
            }
        }
        return false;
    }

    @SuppressWarnings("unchecked")
    private Set<Integer> getNeighbors(HTree graph, int nodeId) throws Exception {
        Object v = graph.get(Integer.valueOf(nodeId));
        return (v instanceof Set) ? (Set<Integer>) v : new HashSet<Integer>();
    }

    private List<Map.Entry<String, Integer>> topKeywords(Map<String, Integer> freq, int limit) {
        List<Map.Entry<String, Integer>> entries = new ArrayList<Map.Entry<String, Integer>>(freq.entrySet());
        Collections.sort(entries, new Comparator<Map.Entry<String, Integer>>() {
            @Override
            public int compare(Map.Entry<String, Integer> a, Map.Entry<String, Integer> b) {
                int d = b.getValue().intValue() - a.getValue().intValue();
                if (d != 0) {
                    return d;
                }
                return a.getKey().compareTo(b.getKey());
            }
        });
        if (entries.size() > limit) {
            return entries.subList(0, limit);
        }
        return entries;
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8" />
    <title>Web-Inf Search Result</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.5; }
        .result { padding: 12px 0; border-bottom: 1px solid #ddd; }
        .score-title { font-size: 18px; font-weight: bold; }
        .meta { color: #555; }
        .links { margin-top: 6px; }
        .links div { margin: 2px 0; }
    </style>
</head>
<body>
<h2>Web-Inf Search Engine</h2>

<%
    request.setCharacterEncoding("UTF-8");
    String query = request.getParameter("query");

    if (query == null || query.trim().length() == 0) {
%>
    <p>No query provided.</p>
    <p><a href="comp4321-proj.html">Back</a></p>
<%
    } else {
        RecordManager recman = null;
        try {
            String appRoot = application.getRealPath("/");
            String stopwordPath = application.getRealPath("/WEB-INF/classes/stopwords.txt");
            if (stopwordPath == null || !new File(stopwordPath).exists()) {
                stopwordPath = appRoot + File.separator + ".." + File.separator + "src" + File.separator + "main" + File.separator + "resource" + File.separator + "stopwords.txt";
            }
            if (!new File(stopwordPath).exists()) {
                stopwordPath = appRoot + File.separator + "stopwords.txt";
            }

            String dbBasePath = resolveDbBasePath(appRoot, application.getInitParameter("dbBasePath"));

            if (dbBasePath == null || !new File(dbBasePath + ".db").exists()) {
                throw new Exception("Cannot find DB file at " + dbBasePath + ".db");
            }

            Object stopStem = createStopStem(stopwordPath);
            recman = RecordManagerFactory.createRecordManager(dbBasePath);

            HTree pageMeta = HTree.load(recman, recman.getNamedObject("pageMeta"));
            HTree bodyIndex = HTree.load(recman, recman.getNamedObject("bodyIndex"));
            HTree titleIndex = HTree.load(recman, recman.getNamedObject("titleIndex"));
            HTree idToUrl = HTree.load(recman, recman.getNamedObject("idToUrl"));
            HTree parentToChildren = HTree.load(recman, recman.getNamedObject("parentToChildren"));
            HTree childToParents = HTree.load(recman, recman.getNamedObject("childToParents"));

            List<List<String>> phrases = new ArrayList<List<String>>();
            List<String> allQueryTerms = new ArrayList<String>();

            Matcher q = QUERY_PATTERN.matcher(query);
            while (q.find()) {
                String phrase = q.group(1);
                String single = q.group(2);
                if (phrase != null) {
                    List<String> phraseTerms = normalizeAndStemTerms(stopStem, phrase);
                    if (!phraseTerms.isEmpty()) {
                        phrases.add(phraseTerms);
                        allQueryTerms.addAll(phraseTerms);
                    }
                } else if (single != null) {
                    List<String> one = normalizeAndStemTerms(stopStem, single);
                    if (!one.isEmpty()) {
                        allQueryTerms.add(one.get(0));
                    }
                }
            }

            if (allQueryTerms.isEmpty()) {
%>
    <p>No valid query terms after stop-word removal.</p>
<%
            } else {
                Map<String, Integer> queryTf = new LinkedHashMap<String, Integer>();
                for (String t : allQueryTerms) {
                    Integer old = queryTf.get(t);
                    queryTf.put(t, Integer.valueOf(old == null ? 1 : old.intValue() + 1));
                }

                int maxQueryTf = 1;
                for (Integer v : queryTf.values()) {
                    if (v.intValue() > maxQueryTf) {
                        maxQueryTf = v.intValue();
                    }
                }

                int docCount = 0;
                FastIterator docKeyIt = pageMeta.keys();
                while (docKeyIt.next() != null) {
                    docCount++;
                }
                if (docCount == 0) {
                    docCount = 1;
                }

                Map<Integer, Double> docDot = new HashMap<Integer, Double>();
                Map<Integer, Double> docNorm = new HashMap<Integer, Double>();
                double queryNorm = 0.0;
                Set<Integer> candidateDocIds = new LinkedHashSet<Integer>();

                for (Map.Entry<String, Integer> queryEntry : queryTf.entrySet()) {
                    String term = queryEntry.getKey();
                    int qtf = queryEntry.getValue().intValue();

                    Map<Integer, Object> bodyPost = getPostingMap(bodyIndex, term);
                    Map<Integer, Object> titlePost = getPostingMap(titleIndex, term);

                    Set<Integer> postingDocs = new HashSet<Integer>();
                    postingDocs.addAll(bodyPost.keySet());
                    postingDocs.addAll(titlePost.keySet());
                    int df = postingDocs.size();
                    if (df == 0) {
                        continue;
                    }

                    double idf = Math.log((double) docCount / (double) df) / Math.log(2.0);
                    if (idf < 0) {
                        idf = 0;
                    }
                    double wq = ((double) qtf / (double) maxQueryTf) * idf;
                    queryNorm += (wq * wq);

                    for (Integer docId : postingDocs) {
                        candidateDocIds.add(docId);

                        Object pageInfo = pageMeta.get(docId);
                        Map<String, Integer> bodyFreq = getBodyFreqMap(pageInfo);
                        Map<String, List<Integer>> titlePos = getPosMap(pageInfo, "titlePositions");

                        int maxTfDoc = 1;
                        for (Integer freqValue : bodyFreq.values()) {
                            if (freqValue != null && freqValue.intValue() > maxTfDoc) {
                                maxTfDoc = freqValue.intValue();
                            }
                        }
                        for (List<Integer> titlePosList : titlePos.values()) {
                            int boosted = (int) Math.round(titlePosList.size() * TITLE_BOOST);
                            if (boosted > maxTfDoc) {
                                maxTfDoc = boosted;
                            }
                        }

                        int bodyTf = 0;
                        Object bodyPosting = bodyPost.get(docId);
                        if (bodyPosting != null) {
                            bodyTf = getPostingFreq(bodyPosting);
                        }

                        int titleTf = 0;
                        Object titlePosting = titlePost.get(docId);
                        if (titlePosting != null) {
                            titleTf = getPostingFreq(titlePosting);
                        }

                        double dtf = bodyTf + (TITLE_BOOST * titleTf);
                        double wd = ((double) dtf / (double) Math.max(1, maxTfDoc)) * idf;

                        Double oldDot = docDot.get(docId);
                        docDot.put(docId, Double.valueOf((oldDot == null ? 0.0 : oldDot.doubleValue()) + (wd * wq)));

                        Double oldNorm = docNorm.get(docId);
                        docNorm.put(docId, Double.valueOf((oldNorm == null ? 0.0 : oldNorm.doubleValue()) + (wd * wd)));
                    }
                }

                queryNorm = Math.sqrt(queryNorm);
                List<ResultRow> ranked = new ArrayList<ResultRow>();

                for (Integer docId : candidateDocIds) {
                    Object pageInfo = pageMeta.get(docId);
                    if (pageInfo == null) {
                        continue;
                    }

                    Map<String, List<Integer>> bodyPos = getPosMap(pageInfo, "bodyPositions");
                    Map<String, List<Integer>> titlePos = getPosMap(pageInfo, "titlePositions");
                    boolean passPhrase = true;
                    for (List<String> phrase : phrases) {
                        boolean inBody = containsPhrase(bodyPos, phrase);
                        boolean inTitle = containsPhrase(titlePos, phrase);
                        if (!inBody && !inTitle) {
                            passPhrase = false;
                            break;
                        }
                    }
                    if (!passPhrase) {
                        continue;
                    }

                    double dot = docDot.containsKey(docId) ? docDot.get(docId).doubleValue() : 0.0;
                    double dNorm = docNorm.containsKey(docId) ? Math.sqrt(docNorm.get(docId).doubleValue()) : 0.0;
                    double score = (queryNorm > 0.0 && dNorm > 0.0) ? (dot / (queryNorm * dNorm)) : 0.0;

                    if (score > 0.0) {
                        ranked.add(new ResultRow(docId.intValue(), score, pageInfo));
                    }
                }

                Collections.sort(ranked, new Comparator<ResultRow>() {
                    @Override
                    public int compare(ResultRow a, ResultRow b) {
                        return Double.compare(b.score, a.score);
                    }
                });

                DecimalFormat scoreFmt = new DecimalFormat("0.000000");
                SimpleDateFormat sdf = new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z", Locale.ENGLISH);

                int showCount = Math.min(MAX_RESULTS, ranked.size());
%>
    <p>Query: <b><%= query %></b></p>
    <p>Total matched documents: <b><%= ranked.size() %></b>, showing top <b><%= showCount %></b>.</p>
<%
                for (int i = 0; i < showCount; i++) {
                    ResultRow row = ranked.get(i);
                    Object pageInfo = row.pageInfo;

                    String title = getStringField(pageInfo, "title");
                    String url = getStringField(pageInfo, "url");
                    long lastModified = getLongField(pageInfo, "lastModified");
                    int size = getIntField(pageInfo, "size");

                    Map<String, Integer> bodyFreq = getBodyFreqMap(pageInfo);
                    List<Map.Entry<String, Integer>> top = topKeywords(bodyFreq, 5);

                    Set<Integer> parents = getNeighbors(childToParents, row.docId);
                    Set<Integer> children = getNeighbors(parentToChildren, row.docId);
%>
    <div class="result">
        <div class="score-title"><%= scoreFmt.format(row.score) %> <a href="<%= url %>" target="_blank"><%= title %></a></div>
        <div><a href="<%= url %>" target="_blank"><%= url %></a></div>
        <div class="meta"><%= sdf.format(new Date(lastModified)) %>, <%= size %></div>
        <div>
<%
                    StringBuilder keywordLine = new StringBuilder();
                    for (int k = 0; k < top.size(); k++) {
                        if (k > 0) {
                            keywordLine.append("; ");
                        }
                        keywordLine.append(top.get(k).getKey()).append(" ").append(top.get(k).getValue());
                    }
%>
            <%= keywordLine.toString() %>
        </div>
        <div class="links">
<%
                    List<Integer> parentList = new ArrayList<Integer>(parents);
                    Collections.sort(parentList);
                    for (Integer pid : parentList) {
                        String pUrl = String.valueOf(idToUrl.get(pid));
%>
            <div>Parent link: <a href="<%= pUrl %>" target="_blank"><%= pUrl %></a></div>
<%
                    }

                    List<Integer> childList = new ArrayList<Integer>(children);
                    Collections.sort(childList);
                    for (Integer cid : childList) {
                        String cUrl = String.valueOf(idToUrl.get(cid));
%>
            <div>Child link: <a href="<%= cUrl %>" target="_blank"><%= cUrl %></a></div>
<%
                    }
%>
        </div>
    </div>
<%
                }
            }
        } catch (Exception ex) {
%>
    <p>Search failed: <%= ex.toString() %></p>
<%
        } finally {
            if (recman != null) {
                try {
                    recman.close();
                } catch (Exception ignored) {
                }
            }
        }
%>
    <p><a href="comp4321-proj.html">Back</a></p>
<%
    }
%>

</body>
</html>
